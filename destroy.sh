#!/bin/bash
set -e

echo "== Destroying website =="
cd website
terraform destroy -auto-approve -var-file="secrets.tfvars"

# Verify nothing was left behind
REMAINING=$(terraform state list | wc -l)
if [ "$REMAINING" -ne 0 ]; then
  echo "ERROR: $REMAINING resources still in state after destroy!"
  terraform destroy -auto-approve -var-file="secrets.tfvars"
  
  REMAINING=$(terraform state list | wc -l)
  if [ "$REMAINING" -ne 0 ]; then
    echo "ERROR: $REMAINING resources still in state after retry:"
    terraform state list
    echo "Require manual intervention to delete the resources"
    exit 1
  fi
fi
echo "Confirmed: State is fully empty"
cd ..
