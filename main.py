import asyncio
import hydra
from src.configs import Config
from src.syncer import Syncer


@hydra.main(config_path="configs", config_name="config")
def main(cfg: Config) -> None:
    asyncio.run(Syncer(cfg).sync())


if __name__ == "__main__":
    main()
