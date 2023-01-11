import asyncio
import hydra
import os
import http

from src.configs import Config
from src.syncer import Syncer
from flask import Flask, jsonify


@hydra.main(config_path="configs", config_name="config")
def main(cfg: Config) -> None:
    syncer = Syncer(cfg)
    port = os.getenv('PORT') or 8080

    if not cfg.enable_http_server:
        asyncio.run(syncer.sync())
        return

    app = Flask(__name__)

    @app.post('/sync')
    async def sync():
        try:
            await syncer.sync()
            return jsonify({'status': 'ok'}, status=http.HTTPStatus.OK)
        except Exception as e:
            syncer.logger.error(
                'ran into error %s while attampting to sync', e)
            return jsonify({'status': 'error', 'msg': 'failed to sync'},
                           status=http.HTTPStatus.INTERNAL_SERVER_ERROR)

    syncer.logger.info('starting http server on %d', port)
    app.run(port=port)


if __name__ == "__main__":
    main()
