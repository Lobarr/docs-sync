import dataclasses


@dataclasses.dataclass()
class Credential:
    email: str = dataclasses.field(default_factory=str)
    password: str = dataclasses.field(default_factory=str)
    # imap.google.com, etc
    imap_server: str = dataclasses.field(default_factory=str)
    imap_port: int = dataclasses.field(default_factory=int)


@dataclasses.dataclass()
class Config:
    credentials: list[Credential] = dataclasses.field(default_factory=list)
    drive_api_token: str = dataclasses.field(default_factory=str)
    enable_http_server: bool = dataclasses.field(default_factory=bool)
    folder_id: str = dataclasses.field(default_factory=str)
    mails_from: list[str] = dataclasses.field(default_factory=list)
    persist_to_firestore: bool = dataclasses.field(default_factory=bool)
    upload_to_drive: bool = dataclasses.field(default_factory=bool)
    emails_processed_limit: int = dataclasses.field(default_factory=int)
