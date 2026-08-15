set -e

echo "== Deploying backend (s3 + DynamoDB) ="
cd backend
terraform init
terraform plan -var-file="secrets.tfvars"
terraform apply -auto-approve -var-file="secrets.tfvars"
cd ..

echo "== Deploying website (website + ALB + monitoring) =="
cd website
terraform init
terraform plan -var-file="secrets.tfvars"
terraform apply -auto-approve -var-file="secrets.tfvars"
cd ..

echo "== Done. Outputs: =="
cd website
terraform output
