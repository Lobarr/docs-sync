import dataclasses


@dataclasses.dataclass()
class Credential:
    email: str = dataclasses.field(default_factory=str)
    password: str = dataclasses.field(default_factory=str)
    # imap.google.com, etc
    imap_server: str = dataclasses.field(default_factory=str)
    imap_port: int = dataclasses.field(default_factory=int)


@dataclasses.dataclass()
class GoogleCreds:
    access_token: str = dataclasses.field(default_factory=str)
    refresh_token: str = dataclasses.field(default_factory=str)
    client_id: str = dataclasses.field(default_factory=str)
    client_secret: str = dataclasses.field(default_factory=str)


@dataclasses.dataclass()
class Config:
    credentials: list[Credential] = dataclasses.field(default_factory=list)
    mails_from: list[str] = dataclasses.field(default_factory=list)
    folder_id: str = dataclasses.field(default_factory=str)
    google_creds: GoogleCreds = dataclasses.field(default_factory=GoogleCreds)
    upload_to_drive: bool = dataclasses.field(default_factory=bool)
    persist_to_firestore: bool = dataclasses.field(default_factory=bool)
