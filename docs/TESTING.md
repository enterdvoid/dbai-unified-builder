# Validation

Run the local checks before changing workflow inputs or extension hooks:

```bash
shellcheck scripts/*.sh extensions/*.sh tests/*.sh
bash tests/test-validate-inputs.sh
```

The GitHub Actions validation workflow additionally runs actionlint against all workflow YAML files. It also checks the embedded Docker Compose configuration and exercises the input validator.
