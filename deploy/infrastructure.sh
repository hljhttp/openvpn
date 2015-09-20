#!/bin/bash

set -e

##
## This script is executed by the CI system in order to ensure that AWS infrastructure is present.
## The following environment variables can be set to control the behaviour of the script:
## ENVIRONMENT : Defines the suffix of several s VPC_NAME, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY and AWS_DEFAULT_REGION must be set.
## The script creates or updates the infrastructure of the Stack in the VPC provided
##

# The name of the stack without the environment suffix
STACK_PREFIX="openvpn"

## Nothing needs to be changed below this line

# Name of the environment
DEFAULT_ENVIRONMENT="dev"
if [[ -z "$ENVIRONMENT" ]]; then
	ENVIRONMENT="$DEFAULT_ENVIRONMENT"
fi

# Default VPC if VPC_NAME is not specified
DEFAULT_VPC="moovel-${ENVIRONMENT}"

# Name of the cloudformation stack of this micro service
STACK_NAME="${STACK_PREFIX}-${ENVIRONMENT}"

# Required name prefix of private subnets
PRIVATE_SUBNET_PREFIX="moovel-private-${ENVIRONMENT}"

# Required name prefix of public subnets
PUBLIC_SUBNET_PREFIX="moovel-public-${ENVIRONMENT}"

# Write the status of the cloud formation stack into the variable STACK_STATUS
function setStackStatus {
	STACK_STATUS=$(aws cloudformation list-stacks | jq -r ".StackSummaries[] | select(.StackName==\"$STACK_NAME\" and .StackStatus!=\"DELETE_COMPLETE\") .StackStatus")
	echo "Status of stack $STACK_NAME: $STACK_STATUS"
}

# Wait until all *IN_PROGRESS stack status have transitioned to their final value and then set the STACK_STATUS variable:
# http://docs.aws.amazon.com/cli/latest/reference/cloudformation/list-stacks.html
function setFinalStackStatus {
	local IS_IN_PROGRESS=true
	while $IS_IN_PROGRESS; do
		setStackStatus
		if [[ "$STACK_STATUS" == *"IN_PROGRESS" ]]; then
			sleep 10
		else
			IS_IN_PROGRESS=false
		fi
	done;
}

# The AWS call to create-stack and update-stack is very similar.
function createOrUpdateStack {
	local CLOUDFORMATION_COMMAND=$1
	local AWS_COMMAND="aws cloudformation \"$CLOUDFORMATION_COMMAND\" \
--stack-name \"$STACK_NAME\" \
--capabilities CAPABILITY_IAM \
--template-body \"file://$(cd $(dirname $0) && pwd)/cloudformation.json\" \
--parameters ParameterKey=VpcID,ParameterValue=\"${VPC_ID}\" \
	ParameterKey=PrivateSubnetIDs,ParameterValue=\"${PRIVATE_SUBNET_IDS//,/\\,}\" \
	ParameterKey=PublicSubnetIDs,ParameterValue=\"${PUBLIC_SUBNET_IDS//,/\\,}\" \
	ParameterKey=Environment,ParameterValue=\"$ENVIRONMENT\""
	echo "Executing: $AWS_COMMAND"
	eval "$AWS_COMMAND"
}

function createStack {
	createOrUpdateStack "create-stack"
	setFinalStackStatus
	if [[ "$STACK_STATUS" != "CREATE_COMPLETE" ]]; then
		echo "Creation of stack $STACK_NAME failed: $STACK_STATUS"
		exit 1
	fi
}

function updateStack {
	createOrUpdateStack "update-stack"
	setFinalStackStatus
	if [[ "$STACK_STATUS" != "UPDATE_COMPLETE" ]]; then
		echo "Update of stack $STACK_NAME failed: $STACK_STATUS"
		exit 1
	fi
}

function deleteStack {
	local AWS_COMMAND="aws cloudformation delete-stack --stack-name \"$STACK_NAME\""
	echo "Executing: $AWS_COMMAND"
	eval "$AWS_COMMAND"
	setFinalStackStatus
	if [[ -n "$STACK_STATUS" ]]; then
		echo "Deletion of stack $STACK_NAME failed: $STACK_STATUS"
		exit 1
	fi
}

# Lookup the id of the VPC
function setVpcId {
	if [[ -z "$VPC_NAME" ]]; then
		VPC_NAME="$DEFAULT_VPC"
	fi
	echo "Searching for ID of VPC '$VPC_NAME'..."
	VPC_ID=$(aws ec2 describe-vpcs | jq -r ".Vpcs[] | select(.Tags[] | select(.Key==\"Name\" and .Value==\"$VPC_NAME\")) .VpcId")
	if [[ -z "$VPC_ID" ]]; then
		echo "No VPC with the name '$VPC_NAME' could be found"
		exit 1
	fi
	echo "Found VPC '$VPC_NAME' with ID '$VPC_ID'"
}


# Create a comma concatenated String of the subnet ids contained in the VPC
function setSubnetIds {
	echo "Searching for subnets of VPC '$VPC_ID'..."
	local SUBNETS=$(aws ec2 describe-subnets | jq -r ".Subnets[] | select(.VpcId==\"$VPC_ID\")")
	PRIVATE_SUBNET_IDS=$(echo $SUBNETS | jq -r ". | select(.Tags[] | select(.Key==\"Name\" and (.Value | startswith(\"$PRIVATE_SUBNET_PREFIX\")))) .SubnetId" | paste -s -d ',' -)
	if [[ -z "$PRIVATE_SUBNET_IDS" ]]; then
		echo "VPC '$VPC_ID' does not contain any subnets whose name start with $PRIVATE_SUBNET_PREFIX"
		exit 1
	fi
	echo "Found private subnets with IDs '$PRIVATE_SUBNET_IDS'"
	PUBLIC_SUBNET_IDS=$(echo $SUBNETS | jq -r ". | select(.Tags[] | select(.Key==\"Name\" and (.Value | startswith(\"$PUBLIC_SUBNET_PREFIX\")))) .SubnetId" | paste -s -d ',' -)
	if [[ -z "$PUBLIC_SUBNET_IDS" ]]; then
		echo "VPC '$VPC_ID' does not contain any subnets whose name start with $PUBLIC_SUBNET_PREFIX"
		exit 1
	fi
	echo "Found public subnets with IDs '$PUBLIC_SUBNET_IDS'"
}

function start {
	setVpcId
	setSubnetIds
	setFinalStackStatus

	# Modify the stack
	if [[ ( "$STACK_STATUS" == *"_FAILED" ) || ( "$STACK_STATUS" == "ROLLBACK_COMPLETE" ) ]]; then
		# Delete the invalid stack
		deleteStack
	fi

	if [[ -n "$STACK_STATUS" ]]; then
		# Stack is valid and can be updated
		updateStack
	else
		# Stack must be created
		createStack
	fi
	RETVAL=$?
	return $RETVAL
}

function stop {
	setFinalStackStatus

	if [[ -n "$STACK_STATUS" ]]; then
		# Delete an existing stack
		deleteStack
	fi
	RETVAL=$?
	return $RETVAL
}

case "$1" in
	start)
		# start or update the cloudformation
		start
		RETVAL=$?
		;;
	stop)
		# remove the cloudformation
		stop
		RETVAL=$?
		;;
	restart)
		# remove and start the cloudformation
		stop
		start
		RETVAL=$?
		;;
	status)
		# print the current status
		setStackStatus
		RETVAL=$?
		;;
	*)
		echo "Usage: $0 {start|stop|status|restart}"
		RETVAL=1
		;;
esac

exit $RETVAL
