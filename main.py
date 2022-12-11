import asyncio
import hydra
from src.configs import Configs
from src.syncer import Syncer


@hydra.main(config_path="configs", config_name="config")
async def main(cfg: Configs) -> None:
    await Syncer(cfg).sync()


if __name__ == "__main__":
    asyncio.run(main())
