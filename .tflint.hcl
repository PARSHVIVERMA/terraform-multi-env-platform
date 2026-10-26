# TFLint configuration: catches mistakes terraform validate does not,
# e.g. unused variables, missing descriptions, invalid AWS values.
config {
  call_module_type = "local"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "aws" {
  enabled = true
  version = "0.38.0" # check https://github.com/terraform-linters/tflint-ruleset-aws/releases for newer versions
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

rule "terraform_documented_variables" {
  enabled = true
}

rule "terraform_documented_outputs" {
  enabled = true
}

rule "terraform_naming_convention" {
  enabled = true
}
