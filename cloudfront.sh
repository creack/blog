SSL_ARN="arn:aws:acm:us-east-1:201844334172:certificate/4ef58faa-96c1-49e6-9fb9-847929ce8062"

BUCKET_NAME="blog.charmes.net-cdn"
LOG_BUCKET_NAME="blog.charmes.net-cdn-logs"

CALLER_REF="`date +%s`" # current second
echo "{
    \"Comment\": \"$BUCKET_NAME Static Hosting\",
    \"Logging\": {
        \"Bucket\": \"$LOG_BUCKET_NAME.s3.amazonaws.com\",
        \"Prefix\": \"${BUCKET_NAME}-cf/\",
        \"Enabled\": true,
        \"IncludeCookies\": false
    },
    \"Origins\": {
        \"Quantity\": 1,
        \"Items\": [
            {
                \"Id\":\"$BUCKET_NAME-origin\",
                \"OriginPath\": \"\",
                \"CustomOriginConfig\": {
                    \"OriginProtocolPolicy\": \"http-only\",
                    \"HTTPPort\": 80,
                    \"OriginSslProtocols\": {
                        \"Quantity\": 3,
                        \"Items\": [
                            \"TLSv1\",
                            \"TLSv1.1\",
                            \"TLSv1.2\"
                        ]
                    },
                    \"HTTPSPort\": 443
                },
                \"DomainName\": \"$BUCKET_NAME.s3-website-$REGION.amazonaws.com\"
            }
        ]
    },
    \"DefaultRootObject\": \"index.html\",
    \"PriceClass\": \"PriceClass_All\",
    \"Enabled\": true,
    \"CallerReference\": \"$CALLER_REF\",
    \"DefaultCacheBehavior\": {
        \"TargetOriginId\": \"$BUCKET_NAME-origin\",
        \"ViewerProtocolPolicy\": \"redirect-to-https\",
        \"DefaultTTL\": 1800,
        \"AllowedMethods\": {
            \"Quantity\": 2,
            \"Items\": [
                \"HEAD\",
                \"GET\"
            ],
            \"CachedMethods\": {
                \"Quantity\": 2,
                \"Items\": [
                    \"HEAD\",
                    \"GET\"
                ]
            }
        },
        \"MinTTL\": 0,
        \"Compress\": true,
        \"ForwardedValues\": {
            \"Headers\": {
                \"Quantity\": 0
            },
            \"Cookies\": {
                \"Forward\": \"none\"
            },
            \"QueryString\": false
        },
        \"TrustedSigners\": {
            \"Enabled\": false,
            \"Quantity\": 0
        }
    },
    \"ViewerCertificate\": {
        \"SSLSupportMethod\": \"sni-only\",
        \"ACMCertificateArn\": \"$SSL_ARN\",
        \"MinimumProtocolVersion\": \"TLSv1\",
        \"Certificate\": \"$SSL_ARN\",
        \"CertificateSource\": \"acm\"
    },
    \"CustomErrorResponses\": {
        \"Quantity\": 2,
        \"Items\": [
            {
                \"ErrorCode\": 403,
                \"ResponsePagePath\": \"/404.html\",
                \"ResponseCode\": \"404\",
                \"ErrorCachingMinTTL\": 300
            },
            {
                \"ErrorCode\": 404,
                \"ResponsePagePath\": \"/404.html\",
                \"ResponseCode\": \"404\",
                \"ErrorCachingMinTTL\": 300
            }
        ]
    },
    \"Aliases\": {
        \"Quantity\": 1,
        \"Items\": [
            \"blog.charmes.net\"
        ]
    }
}" > distroConfig.json
