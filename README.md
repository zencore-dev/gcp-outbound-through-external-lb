# Demo: How to access the internet using a Load Balancer's external IP address in Google Cloud

## Steps for deploying the demo

1. Create a new Google Cloud project
2. Switch to the new project and open the Cloud Shell
3. Clone this repository: `git clone https://github.com/zencore-dev/gcp-outbound-through-external-lb.git`
4. Change to the directory of this repository: `cd gcp-outbound-through-external-lb`
5. Run `terraform init` to initialize the Terraform configuration
6. Run `terraform apply -var "project_id=$GOOGLE_CLOUD_PROJECT" -var "region=us-east1"` to deploy the demo. Change the
region to another one if you wish.

## How to test the demo

1. In the Google Cloud Console, go to the Compute Engine -> VM Instances page.
2. SSH into the instance named `workload`.
3. Run `curl https://ifconfig.co` to test the internet access. It will show the external IP address of the Load Balancer.
4. Run `ping 8.8.8.8` and leave it running.
5. Shut down the instance named `nat-1`. The ping should still work, as it will fail over to the other NAT instance.

VPC flow logs are enabled for all the subnets, so you can check the logs to see the traffic flow, and observe the failover.

## How to clean up

Delete the project that you created in the Google Cloud Console.