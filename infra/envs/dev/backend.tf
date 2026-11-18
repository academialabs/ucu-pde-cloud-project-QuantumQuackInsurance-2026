terraform {
  backend "gcs" {
    # El bucket se pasa en init: terraform init -backend-config="bucket=<PROJECT_ID>-tfstate"
    prefix = "envs/dev"
  }
}
