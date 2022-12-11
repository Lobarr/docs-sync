import base64
import collections
import dataclasses
import datetime
import email
import hashlib
import imaplib
import logging
import pprint

from google.cloud import firestore
from google.cloud import exceptions
from googleapiclient.discovery import build
from google.oauth2.credentials import Credentials

from src.configs import Config


@dataclasses.dataclass
class EmailAttachment:
    filename: str = dataclasses.field(default_factory=str)
    content: bytes = dataclasses.field(default_factory=bytes)
    content_type: str = dataclasses.field(default_factory=str)
    drive_url: str = dataclasses.field(default_factory=str)

    @property
    def content_hash(self) -> str:
        return hashlib.sha256(self.content).hexdigest()

    @property
    def content_size(self) -> str:
        return len(self.content)

    @property
    def uid(self) -> str:
        return hashlib.sha256(
            ':'.join([
                self.file_name,
                self.content_hash,
                self.content_type,
            ])).hexdigest()


@dataclasses.dataclass()
class ParsedEmail:
    attachments: list[EmailAttachment] = dataclasses.field(
        default_factory=list)
    last_parsed_at: datetime = dataclasses.field(default_factory=datetime)
    message_id: str = dataclasses.field(default_factory=str)
    sent_at: datetime = dataclasses.field(default_factory=datetime)
    sent_from: str = dataclasses.field(default_factory=str)
    sent_to: str = dataclasses.field(default_factory=str)
    subject: str = dataclasses.field(default_factory=str)

    @property
    def subject_hash(self) -> str:
        return hashlib.sha256(self.subject).hexdigest()

    @property
    def uid(self) -> str:
        return hashlib.sha256(
            ':'.join([
                self.sent_from,
                self.sent_to,
                self.subject_hash,
                self.created_at,
            ])).hexdigest()


class Syncer:
    def __init__(self, config: Config):
        self.logger = logging.getLogger()
        self.config: Config = config
        self.mailboxes: dict[str,
                             imaplib.IMAP4_SSL] = collections.defaultdict(dict)

        # connect to mailboxes provided in configs
        for credential in self.config.credentials:
            try:
                mailbox = imaplib.IMAP4_SSL(
                    credential.imap_server, credential.imap_port)
                mailbox.login(credential.email, credential.password)
                mailbox.select('inbox')
                self.mailboxes[credential.email] = mailbox
            except Exception as e:
                logging.fatal('failed to create mailbox due to %s', e)
                exit(1)

        info = {
            'access_token': self.config.google_creds.access_token,
            'refresh_token': self.config.google_creds.refresh_token,
            'token_uri': 'https://oauth2.googleapis.com/token',
            'client_id': self.config.google_creds.client_id,
            'client_secret': self.config.google_creds.client_secret,
        }
        creds = Credentials.from_authorized_user_info(info=info)

        # connect to firestore in order to persist progress
        if self.config.persist_to_firestore:
            self.db_client = firestore.Client(
                credentials=creds)
            self.parsed_emails_collection = self.db_client.collection(
                u'parsed_emails')
        else:
            self.db_client = None
            self.parsed_emails_collection = None

        # connect to google drive
        if self.config.upload_to_drive:
            self.drive_service = build('drive', 'v3', credentials=creds)
        else:
            self.drive_service = None

    async def _upload_attachments(self, parsed_email: ParsedEmail):
        if not self.config.upload_to_drive:
            return

        for attachment in parsed_email.attachments:
            try:
                file_content_b64 = base64.urlsafe_b64encode(
                    attachment.content.encode('utf-8')).decode('utf-8')

                file_metadata = {
                    'name': attachment.filename,
                    'parents': [self.config.folder_id],
                    'mimeType': attachment.content_type,
                }

                file_content = {
                    'data': file_content_b64,
                    'mimeType': attachment.content_type,
                    'encoding': 'base64'
                }

                file = self.drive_service.files().create(
                    body=file_metadata, media_body=file_content).execute()

                attachment.drive_url = file['webContentLink']
            except Exception as e:
                logging.error(
                    'failed to upload parsed email %s attachment to google drive due to %s', parsed_email.uid, e)

    async def _persist_parsed_email(self, parsed_email: ParsedEmail):
        if not self.config.persist_to_firestore:
            return

        try:
            existing_mail_ref = self.parsed_emails_collection.document(
                parsed_email.uid)
            existing_mail = existing_mail_ref.get()

            if existing_mail.exists:
                existing_mail_ref.update({
                    'last_parsed_at': parsed_email.last_parsed_at
                })
                self.logger.info('updating last_parted_at for parsed email %s to %s',
                                 parsed_email.uid, parsed_email.last_parsed_at)
            else:
                existing_mail_ref.set(parsed_email)
                self.logger.info(
                    'persisted context about parsed email %s', parsed_email.uid)
        except Exception as e:
            self.logger.error(
                'failed to write parsed email %s to firestore due to %s', parsed_email.uid, e)

    async def sync(self):
        # peforms processing on each provided credential
        for credential in self.config.credentials:
            self.logger.info('processing emails sent to %s', credential.email)

            mailbox = self.mailboxes[credential.email]

            # process emails from each provided email source
            for sent_from in self.configs.mails_from:
                self.logger.info(
                    'processing emails sent from %s', credential.email)
                _, data = mailbox.search(None, f'FROM {sent_from}')

                for email_id in data[0].split():
                    self.logger.info('processing email %s', email_id)

                    _, data = mailbox.fetch(email_id, '(RFC822)')
                    raw_email_message = data[0][1]
                    email_message = email.message_from_bytes(
                        raw_email_message)

                    parsed_email = ParsedEmail(
                        last_parsed_at=datetime.datetime.now(),
                        sent_from=sent_from,
                        sent_to=credential.email,
                    )

                    if 'subject' in email_message:
                        parsed_email.subject = email_message['subject']

                    if 'message-id' in email_message:
                        parsed_email.message_id = email_message['message-id']

                    if 'date' in email_message:
                        parsed_email.sent_at = email_message['date']

                    for part in email_message.walk():
                        # parse attachements
                        if part.get_content_disposition() == 'attachment':
                            filename = part.get_filename()
                            content = part.get_payload(decode=True)
                            content_type = part.get_content_type()
                            attachment = EmailAttachment(
                                filename=filename,
                                content=content,
                                content_type=content_type,
                            )
                            parsed_email.attachments.append(attachment)

                    self.logger.info('parsed email %s',
                                     pprint.pformat(parsed_email))

                    await self._upload_attachments(parsed_email)
                    await self._persist_parsed_email(parsed_email)
