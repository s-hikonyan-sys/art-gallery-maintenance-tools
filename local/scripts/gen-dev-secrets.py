#!/usr/bin/env python3
"""
開発用シークレットファイル生成スクリプト
make gen-secrets から呼び出される

事前に cryptography パッケージが必要:
  pip install cryptography

art-gallery-secrets の SecretManager と同一ロジック（PBKDF2HMAC + Fernet）で暗号化する。
暗号化フォーマット: encrypted:<base64_encoded_value>
"""

import base64
import secrets
import sys
from pathlib import Path

try:
    from cryptography.fernet import Fernet
    from cryptography.hazmat.primitives import hashes
    from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
except ImportError:
    print("エラー: cryptography パッケージが必要です")
    print("  pip install cryptography")
    sys.exit(1)

LOCAL_CONF_DIR = Path(
    "/home/homepage/project/my_homepage/replace_work/art-gallery-maintenance-tools/local/conf"
)
CONFIG_FILE = LOCAL_CONF_DIR / "secrets/config/config.yaml"
SECRETS_FILE = LOCAL_CONF_DIR / "secrets/config/secrets.yaml.encrypted"

DEV_DB_PASSWORD = "dev_password_local_12345"


def create_cipher(secret_key: str) -> Fernet:
    """art-gallery-secrets の SecretManager と同一ロジックで Fernet cipher を生成."""
    kdf = PBKDF2HMAC(
        algorithm=hashes.SHA256(),
        length=32,
        salt=b"art_gallery_salt",
        iterations=100000,
    )
    key = base64.urlsafe_b64encode(kdf.derive(secret_key.encode()))
    return Fernet(key)


def encrypt_value(secret_key: str, plaintext: str) -> str:
    """平文を暗号化して "encrypted:<base64>" フォーマットで返す."""
    cipher = create_cipher(secret_key)
    encrypted = cipher.encrypt(plaintext.encode())
    encrypted_b64 = base64.urlsafe_b64encode(encrypted).decode()
    return f"encrypted:{encrypted_b64}"


def main():
    # 設定ファイルの存在確認
    if not CONFIG_FILE.exists():
        print(f"エラー: {CONFIG_FILE} が見つかりません")
        print("先に make setup を実行してください")
        sys.exit(1)

    # ランダムな secret_key（パスフレーズ）を生成
    secret_key = secrets.token_urlsafe(32)

    # 開発用 DB パスワードを暗号化
    encrypted_password = encrypt_value(secret_key, DEV_DB_PASSWORD)

    # config.yaml の secret_key を更新
    config_content = CONFIG_FILE.read_text(encoding="utf-8")
    new_lines = []
    for line in config_content.splitlines():
        if line.strip().startswith("secret_key:"):
            new_lines.append(f'secret_key: "{secret_key}"')
        else:
            new_lines.append(line)
    CONFIG_FILE.write_text("\n".join(new_lines) + "\n", encoding="utf-8")
    print(f"[OK] secret_key を config.yaml に設定しました")
    print(f"     → {CONFIG_FILE}")

    # secrets.yaml.encrypted を生成
    secrets_content = f"""database:
  password: "{encrypted_password}"
"""
    SECRETS_FILE.write_text(secrets_content, encoding="utf-8")
    print(f"[OK] secrets.yaml.encrypted を生成しました")
    print(f"     → {SECRETS_FILE}")
    print(f"     開発用 DB パスワード: {DEV_DB_PASSWORD}")
    print()
    print("[INFO] このファイルは開発用です。本番環境には使用しないでください。")


if __name__ == "__main__":
    main()
