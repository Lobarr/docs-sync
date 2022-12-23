import asyncio
import hydra
import os

from src.configs import Config
from src.syncer import Syncer
from flask import Flask, jsonify


@hydra.main(config_path="configs", config_name="config")
def main(cfg: Config) -> None:
    syncer = Syncer(cfg)

    if not cfg.enable_http_server:
        asyncio.run(syncer.sync())
        return

    app = Flask(__name__)

    @app.post('/sync')
    async def sync():
        try:
            await syncer.sync()
            return jsonify({'status': 'ok'})
        except Exception as e:
            syncer.logger.error(
                'ran into error %s while attampting to sync', e)
            return jsonify({'status': 'error', 'msg': 'failed to sync'})

    app.run(port=os.getenv('PORT') or 8080)


if __name__ == "__main__":
    main()
