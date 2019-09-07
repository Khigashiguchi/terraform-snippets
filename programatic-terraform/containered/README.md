```
aws ssm put-parameter --name '/db/password' --type SecureString \ --value 'ModifiedStrongPassword!' --overwrite --profile

aws rds modify-db-instance --db-instance-identifier 'example' \ --master-user-password 'NewMasterPassword!' --profile study-terraform
```