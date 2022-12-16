import base64
import collections
import dataclasses
import datetime
import email
import hashlib
import imaplib
import json
import logging
import pprint

from dateutil import parser
from google.cloud import firestore
from googleapiclient.discovery import build
from google.oauth2.credentials import Credentials

from src.configs import Config, Credential


_PARSED_EMAILS_COLLECTION = 'parsed_emails'


@dataclasses.dataclass
class EmailAttachment(json.JSONEncoder):
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
        payload = ':'.join([
            self.filename,
            self.content_hash,
            self.content_type,
        ]).encode('utf-8')
        return hashlib.sha256(payload).hexdigest()

    def default(self, o):
        # omit self.content when serializing to json
        return {
            'content_hash': self.content_hash,
            'content_size': self.content_size,
            'content_type': self.content_type,
            'drive_url': self.drive_url,
            'filename': self.filename,
            'uid': self.uid
        }


@dataclasses.dataclass()
class ParsedEmail:
    attachments: list[EmailAttachment] = dataclasses.field(
        default_factory=list)
    email_id: str = dataclasses.field(default_factory=str)
    last_parsed_at: float = dataclasses.field(default_factory=float)
    message_id: str = dataclasses.field(default_factory=str)
    sent_at: float = dataclasses.field(default_factory=float)
    sent_from: str = dataclasses.field(default_factory=str)
    sent_to: str = dataclasses.field(default_factory=str)
    subject: str = dataclasses.field(default_factory=str)

    @property
    def subject_hash(self) -> str:
        return hashlib.sha256(self.subject.encode('utf-8')).hexdigest()

    @property
    def uid(self) -> str:
        payload = ':'.join([
            self.sent_from,
            self.sent_to,
            self.subject_hash,
            self.message_id,
            self.email_id,
            str(self.sent_at),
        ]).encode('utf-8')
        return hashlib.sha256(payload).hexdigest()


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
                logging.fatal(
                    'failed to create mailbox to %s due to %s', credential.email, e)
                exit(1)

        # TODO: figure out how to auth with drive and firestore
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
                _PARSED_EMAILS_COLLECTION)
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

    async def _process_email(
        self,
        email_id: bytes,
        mailbox: imaplib.IMAP4_SSL,
        sent_from: str,
        credential: Credential,
    ):
        decoded_email_id = email_id.decode('utf-8')
        self.logger.info('processing email %s', decoded_email_id)

        _, data = mailbox.fetch(email_id, '(RFC822)')
        raw_email_message = data[0][1]
        email_message = email.message_from_bytes(
            raw_email_message)

        parsed_email = ParsedEmail(
            last_parsed_at=datetime.datetime.now(),
            sent_from=sent_from,
            sent_to=credential.email,
            email_id=decoded_email_id,
        )

        if 'subject' in email_message:
            parsed_email.subject = email_message['subject']

        if 'message-id' in email_message:
            parsed_email.message_id = email_message['message-id']

        if 'date' in email_message:
            parsed_email.sent_at = parser.parse(
                email_message['date']).timestamp()

        for part in email_message.walk():
            # parse attachements
            if part.get_content_disposition() == 'attachment' and part.get_content_type() != "text/html":
                filename = part.get_filename()
                content = part.get_payload(decode=True)
                content_type = part.get_content_type()
                attachment = EmailAttachment(
                    filename=filename,
                    content=content,
                    content_type=content_type,
                )
                parsed_email.attachments.append(attachment)

                self.logger.info('parsed attachment \"%s\" of size %d and content type %s for email %s',
                                 attachment.filename, attachment.content_size, attachment.content_type, parsed_email.uid)

        if not parsed_email.attachments:
            self.logger.info(
                'skipping email %s becuase it has no attachments', parsed_email.uid)
            return

        self.logger.info('parsed email %s',
                         parsed_email.uid)

        await self._upload_attachments(parsed_email)
        await self._persist_parsed_email(parsed_email)

    async def sync(self):
        # peforms processing on each provided credential
        for credential in self.config.credentials:
            self.logger.info('processing emails sent to %s', credential.email)

            mailbox = self.mailboxes[credential.email]

            # process emails from each provided email source
            for sent_from in self.config.mails_from:
                self.logger.info(
                    'processing emails sent from %s', sent_from)
                _, data = mailbox.search(None, f'FROM {sent_from}')

                for email_id in data[0].split():
                    await self._process_email(email_id, mailbox, sent_from, credential)
