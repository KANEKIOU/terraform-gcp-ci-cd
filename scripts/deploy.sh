#!/bin/bash
set -e

# --- 引数チェック ---
if [ -z "$1" ]; then
  echo "エラー: デプロイ対象の環境を指定してください (例: staging, prod)"
  exit 1
fi
ENVIRONMENT="$1"


# --- 設定 ---
FUNCTION_NAME="hello-world-function"
FUNCTION_SOURCE_DIR_NAME="hello_world"


# --- パス設定 ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}/.."
TERRAFORM_DIR="${PROJECT_ROOT}/terraform"
BUILD_DIR="${PROJECT_ROOT}/build"
SRC_DIR="${PROJECT_ROOT}/src"
SA_KEY_FILE="${PROJECT_ROOT}/credentials/${ENVIRONMENT}-sa-key.json"


# --- メイン処理 ---
main() {
  echo "--- Step 0: GCPへの認証 (${ENVIRONMENT}) ---"
  if [ ! -f "${SA_KEY_FILE}" ]; then
    echo "エラー: サービスアカウントキーが見つかりません: ${SA_KEY_FILE}"
    exit 1
  fi
  gcloud auth activate-service-account --key-file="${SA_KEY_FILE}"
  export GOOGLE_APPLICATION_CREDENTIALS="${SA_KEY_FILE}"
  echo "✓ 認証完了"

  echo "--- Step 1: ソースコードをZIP化 ---"
  mkdir -p "${BUILD_DIR}"
  local zip_file_path="${BUILD_DIR}/${FUNCTION_NAME}.zip"
  (cd "${SRC_DIR}/${FUNCTION_SOURCE_DIR_NAME}" && zip -r "${zip_file_path}" . -x "*.pyc" "__pycache__/*")
  echo "✓ ZIPファイルを作成"

  echo "--- Step 2: ZIPファイルをTerraformディレクトリにコピー ---"
  cp "${zip_file_path}" "${TERRAFORM_DIR}/"
  echo "✓ コピー完了"

  cd "${TERRAFORM_DIR}"

  echo "--- Step 3: Terraform Workspaceの選択 ---"
  terraform workspace select "${ENVIRONMENT}" || terraform workspace new "${ENVIRONMENT}"
  echo "✓ Workspaceを'${ENVIRONMENT}'に設定"

  echo "--- Step 4: Terraformの初期化 ---"
  terraform init
  echo "✓ 初期化完了"

  echo "--- Step 5: Terraformの実行計画を作成 ---"
  # -var-fileで環境ごとの設定ファイルのみを読み込む
  terraform plan \
    -var-file="environments/${ENVIRONMENT}.tfvars" \
    -out=tfplan
  echo "✓ 実行計画を作成完了"

  # CI/CD環境では自動承認
  if [ "${CI}" = "true" ]; then
    echo "--- Step 6: Terraformの変更を自動適用 (CI/CD) ---"
    terraform apply -auto-approve "tfplan"
  else
    # ローカル環境では対話形式で確認
    echo "--- Step 6: Terraformの変更を適用 ---"
    read -p "環境'${ENVIRONMENT}'に上記の計画で変更を適用しますか？ (y/N): " ANSWER
    if [ "$ANSWER" != "y" ]; then
      echo "デプロイをキャンセルしました。"
      exit 0
    fi
    terraform apply "tfplan"
  fi

  echo "✓ デプロイが正常に完了しました。"
}

# スクリプト実行
main
