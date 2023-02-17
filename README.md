# Demo: how to access the internet using a Load Balancer's external IP address in Google Cloud

## Steps for deploying the demo

1. Create a new Google Cloud project
2. Switch to the new project and open the Cloud Shell
3. Clone this repository: `git clone https://github.com/zencore-dev/gcp-outbound-through-external-lb.git`
4. Change to the directory of this repository: `cd gcp-outbound-through-external-lb`
5. Run `terraform init` to initialize the Terraform configuration
6. Run `terraform apply -var "project_id=$GOOGLE_CLOUD_PROJECT" -var "region=us-east1"` to deploy the demo. Change the
region to another one if you wish.

