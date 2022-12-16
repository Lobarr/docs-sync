import os
import asyncio
import hydra
from src.configs import Config
from src.syncer import Syncer
from flask import Flask, jsonify


@hydra.main(config_path="configs", config_name="config")
def main(cfg: Config) -> None:
    syncer = Syncer(cfg)

    if cfg.enable_http_server:
        app = Flask(__name__)

        @app.post('/sync')
        async def sync():
            try:
                await syncer.sync()
                return jsonify({'status': 'ok'})
            except Exception as e:
                return jsonify({'status': 'error', 'msg': str(e)})

        app.run(port=os.getenv('PORT') or 8080)
    else:
        asyncio.run(syncer.sync())


if __name__ == "__main__":
    main()
