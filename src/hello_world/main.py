import os
from flask import Flask

# Flaskアプリケーションのインスタンスを作成
# この 'app' がTerraformのentry_pointで指定される
app = Flask(__name__)


@app.route("/")
def hello_world():
    """リクエストに対してシンプルな挨拶を返す"""
    # 環境変数から名前を取得（なければ 'World' を使う）
    return f"Hello world this is main"
