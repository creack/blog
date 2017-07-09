#!/usr/bin/env bash

# TODO: Get rid of the "\t"s, check why column -t fails..

# Set stop on error flag.
set -e

function verboseecho() {
    if [ "$verbose" = "1" ]; then
	echo -e "$@" >&2
    fi
}

function errecho() {
    echo $@ >&2
    exit 1
}

# Sanity check.
function sanitycheck() {
    ## Check for jq.
    verboseecho -n "Checking for jq cli\t\t\t\t\t\t"
    hash jq || errecho "Jq cli npt fonud, please install. (brew, apt-get, yum pacman, etc..)"
    verboseecho "[OK]"
    ## Check for aws cli.
    verboseecho -n "Checking for aws cli\t\t\t\t\t\t"
    hash aws || errecho "Aws cli not found, please install. (brew, pip, apt-get, yum, pacman, etc..)"
    verboseecho "[OK]"
    ## Check for aws credentials / access to s3.
    verboseecho -n "Checking for aws credentials / permissions\t\t\t"
    aws s3 ls > /dev/null || errecho "Aws user not configured or doesn't have access to s3.."
    verboseecho "[OK]"
}

function s3check() {
    export cdn_bucket_name=$1
    export log_bucket_name=$2

    # Check if the buckets exist.
    verboseecho "CDN bucket: $cdn_bucket_name"
    verboseecho -n "Checking for cdn bucket\t\t\t\t\t\t"
    aws s3 ls s3://$cdn_bucket_name >& /dev/null || export missing_cdn_bucket=1
    [ "$missing_cdn_bucket" = "1" ] && verboseecho "[MISSING]" || verboseecho "[OK]"

    verboseecho "Log bucket: $log_bucket_name"
    verboseecho -n "Checking for log bucket\t\t\t\t\t\t"
    aws s3 ls s3://$log_bucket_name >& /dev/null || export missing_log_bucket=1
    [ "$missing_log_bucket" = "1" ] && verboseecho "[MISSING]" || verboseecho "[OK]"

    # Check if AWS has the proper permisisons on the bucket.
    verboseecho -n "Checking for READ_ACP permission on log bucket\t\t\t"
    [ -n "$(aws s3api get-bucket-acl --bucket $log_bucket_name 2> /dev/null | jq '.Grants[] | select(.Permission == "READ_ACP") | select(.Grantee.URI == "http://acs.amazonaws.com/groups/s3/LogDelivery")' 2> /dev/null)" ] || export missing_read_perm=1
    [ "$missing_read_perm" = "1" ] && verboseecho "[MISSING]" || verboseecho "[OK]"

    verboseecho -n "Checking for WRITE permission on log bucket\t\t\t"
    [ -n "$(aws s3api get-bucket-acl --bucket $log_bucket_name 2> /dev/null | jq '.Grants[] | select(.Permission == "WRITE") | select(.Grantee.URI == "http://acs.amazonaws.com/groups/s3/LogDelivery")' 2> /dev/null)" ] || export missing_write_perm=1
    [ "$missing_write_perm" = "1" ] && verboseecho "[MISSING]" || verboseecho "[OK]"

    # Check logging target prefix.
    verboseecho -n "Checking for logging target prefix\t\t\t\t"
    [ "$(aws s3api get-bucket-logging --bucket blog.charmes.net-cdn 2> /dev/null | jq -r '.LoggingEnabled.TargetPrefix' 2> /dev/null)" = "$cdn_bucket_name" ] || export missing_logging_target_prefix=1
    [ "$missing_logging_target_prefix" = "1" ] && verboseecho "[MISSING]" || verboseecho "[OK]"
    # Check logging target bucket.
    verboseecho -n "Checking for logging target bucket\t\t\t\t"
    [ "$(aws s3api get-bucket-logging --bucket blog.charmes.net-cdn 2> /dev/null | jq -r '.LoggingEnabled.TargetBucket' 2> /dev/null)" = "$log_bucket_name" ] || export missing_logging_target_bucket=1
    [ "$missing_logging_target_bucket" = "1" ] && verboseecho "[MISSING]" || verboseecho "[OK]"
}

function checkall() {
    sanitycheck $@
    s3check $@
}

function s3_create_buckets() {
    # Create CDN bucket.
    if [ "$missing_cdn_bucket" = "1" ]; then
	verboseecho "Missing cnd bucket, creating it.."
	aws s3 mb s3://$cdn_bucket_name
	verboseecho "Done"
    fi
    # Create log bucket.
    if [ "$missing_log_bucket" = "1" ]; then
	verboseecho "Missing log bucket, creating it.."
	aws s3 mb s3://$log_bucket_name
	verboseecho "Done"
    fi
    # Grant READ-ACP and WRITE permission to AWS on log bucket.
    if [ "$missing_read_perm" = "1" ] || [ "$missing_write_perm" = "1" ]; then
	# Wait a bit to make sure the bucket exists.
	[ "$missing_log_bucket" = "1" ] && sleep 1
	verboseecho -n "Granting READ-ACP and WRITE permissions to AWS on log bucket\t"
	aws s3api put-bucket-acl \
	    --bucket $log_bucket_name \
	    --grant-read-acp 'URI="http://acs.amazonaws.com/groups/s3/LogDelivery"' \
	    --grant-write    'URI="http://acs.amazonaws.com/groups/s3/LogDelivery"'
	verboseecho "[OK]"
    fi
}

function s3_web_setup() {
    # Setup logging.
    if [ "$missing_logging_target_prefix" = "1" ] || [ "$missing_logging_target_bucket" = 1 ]; then
	# Wait a bit to make sure the bucket exists.
	[ "$missing_log_bucket" = "1" ] || [ "$missing_cdn_bucket" = "1" ] && sleep 1
	verboseecho "Setting up logging.."
	log_policy='{"LoggingEnabled":{"TargetBucket":"'$log_bucket_name'","TargetPrefix":"'$cdn_bucket_name'"}}'
	aws s3api put-bucket-logging --bucket $cdn_bucket_name --bucket-logging-status $log_policy
	verboseecho "Done"
    fi

    # Create website config file if it does not exist.
    # TODO: Create templates for hugo and some others.
    [ -f website.json ] || cat << EOF > website.json
{
    "IndexDocument": {
        "Suffix": "index.html"
    },
    "ErrorDocument": {
        "Key": "404.html"
    },
    "RoutingRules": [
        {
            "Redirect": {
                "ReplaceKeyWith": "index.html"
            },
            "Condition": {
                "KeyPrefixEquals": "/"
            }
        }
    ]
}
EOF
    # Create the website itselt.
    aws s3api put-bucket-website --bucket $cdn_bucket_name --website-configuration file://website.json

}

# Metadata
## Domain name / AWS Region.
DOMAIN="blog.charmes.net"
REGION="us-east-1"

## Infer two bucket names for the blog. Content (CDN) and Logs.
BUCKET_NAME="${DOMAIN}-cdn"
LOG_BUCKET_NAME="${BUCKET_NAME}-logs"

checkall $BUCKET_NAME $LOG_BUCKET_NAME
verboseecho
s3_create_buckets
s3_web_setup

verboseecho "All Done"
