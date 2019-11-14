figlet ccloud login

figlet Create an environment
CONFLUENT_CLUSTER_NAME=my_cluster_$RANDOM
ccloud environment create $CONFLUENT_CLUSTER_NAME
CONFLUENT_ENVIRONMENT_ID=$(ccloud environment list | grep $CONFLUENT_CLUSTER_NAME | awk '{print $1}')
ccloud environment use $CONFLUENT_ENVIRONMENT_ID

figlet Create a cluster
ccloud kafka cluster list
CONFLUENT_CLUSTER=$(ccloud kafka cluster create $CONFLUENT_CLUSTER_NAME \
    --cloud azure \
    --region westeurope)
echo $CONFLUENT_CLUSTER
CONFLUENT_CLUSTER_ID=$(echo $CONFLUENT_CLUSTER | grep "Id" | awk '{print $4}')
CONFLUENT_BOOTSTRAP_SERVER=$(echo $CONFLUENT_CLUSTER | grep "| Endpoint" | awk '{print $4}' | cut -d '/' -f 3)
ccloud kafka cluster use $CONFLUENT_CLUSTER_ID

echo $CONFLUENT_CLUSTER_NAME bootstrap server is $CONFLUENT_BOOTSTRAP_SERVER

figlet Create an api-key
CONFLUENT_API=$(ccloud api-key create)
echo $CONFLUENT_API
CONFLUENT_APIKEY=$(echo $CONFLUENT_API | grep "API Key" | awk '{print $5}')
CONFLUENT_SECRET=$(echo $CONFLUENT_API | grep "Secret" | awk '{print $4}')
ccloud api-key use $CONFLUENT_APIKEY

figlet List all topics
ccloud kafka topic list
CONFLUENT_TOPIC=my_topic_$RANDOM

figlet Create a topic
ccloud kafka topic create $CONFLUENT_TOPIC --partitions 1
ccloud kafka topic list
ccloud kafka topic describe $CONFLUENT_TOPIC

figlet Create data
seq 5 | ccloud kafka topic produce $CONFLUENT_TOPIC

figlet Consume it back
ccloud kafka topic consume --from-beginning $CONFLUENT_TOPIC

figlet Consume via regular kafka-console-consumer
rm -f .properties
cat > .properties <<DELIM
bootstrap.servers=$CONFLUENT_BOOTSTRAP_SERVER
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required \
  password="$CONFLUENT_SECRET" \
  username="$CONFLUENT_APIKEY";
sasl.mechanism=PLAIN
security.protocol=SASL_SSL
ssl.endpoint.identification.algorithm=https
DELIM

$CONFLUENT_HOME/bin/kafka-console-consumer \
    --consumer.config .properties \
    --bootstrap-server $CONFLUENT_BOOTSTRAP_SERVER \
    --topic $CONFLUENT_TOPIC \
    --from-beginning

figlet Consume via proxy
export CONFLUENT_BOOTSTRAP_SERVER
export CONFLUENT_APIKEY
export CONFLUENT_SECRET
docker-compose up -d
docker-compose ps
docker-compose logs kafka-proxy
docker-compose exec kafka-client \
    kafka-console-consumer \
    --bootstrap-server kafka-proxy:9092 \
    --topic $CONFLUENT_TOPIC \
    --from-beginning

figlet Performance test with direct access
$CONFLUENT_HOME/bin/kafka-producer-perf-test \
    --topic $CONFLUENT_TOPIC \
    --producer.config .properties \
    --throughput -1 \
    --num-records 1000000 \
    --record-size 500 \
    --producer-props \
        bootstrap.servers=$CONFLUENT_BOOTSTRAP_SERVER \
        linger.ms=400 \
        acks=1 \
        batch.size=1000000 \
        compression.type=lz4 \
    --print-metrics

figlet Lets create azure blob storage container
AZURE_RANDOM=$RANDOM
AZURE_RESOURCE_GROUP=delete$AZURE_RANDOM
AZURE_ACCOUNT_NAME=delete$AZURE_RANDOM
AZURE_CONTAINER_NAME=delete$AZURE_RANDOM
AZURE_REGION=westeurope
az login
az group create \
    --name $AZURE_RESOURCE_GROUP \
    --location $AZURE_REGION
az storage account create \
    --name $AZURE_ACCOUNT_NAME \
    --resource-group $AZURE_RESOURCE_GROUP \
    --location $AZURE_REGION \
    --sku Standard_LRS \
    --encryption blob
az storage container create \
    --account-name $AZURE_ACCOUNT_NAME \
    --name $AZURE_CONTAINER_NAME
AZURE_ACCOUNT_KEY=$(az storage account keys list \
    --account-name $AZURE_ACCOUNT_NAME \
    --resource-group $AZURE_RESOURCE_GROUP \
    --output table \
    | grep key1 | awk '{print $3}')

echo Enable the confluent connector
echo TOPIC=$CONFLUENT_TOPIC 
echo KAFKA_API_KEY=$CONFLUENT_APIKEY
echo KAFKA_API_SECRET=$CONFLUENT_SECRET
echo AZURE_ACCOUNT_NAME=$AZURE_ACCOUNT_NAME
echo AZURE_ACCOUNT_KEY=$AZURE_ACCOUNT_KEY
echo AZURE_CONTAINER_NAME=$AZURE_CONTAINER_NAME

az storage blob list \
    --account-name $AZURE_ACCOUNT_NAME \
    --container-name $AZURE_CONTAINER_NAME \
    --output table

open https://confluent.cloud/environments/$CONFLUENT_ENVIRONMENT_ID/clusters/$CONFLUENT_CLUSTER_ID/connectors/new-sink/AzureBlobSink

az storage blob list \
    --account-name $AZURE_ACCOUNT_NAME \
    --container-name $AZURE_CONTAINER_NAME \
    --output table

figlet Tear everything down
docker-compose down -v
ccloud api-key delete $CONFLUENT_APIKEY
ccloud kafka topic delete $CONFLUENT_TOPIC
ccloud kafka cluster delete $CONFLUENT_CLUSTER_ID
ccloud environment delete $CONFLUENT_ENVIRONMENT_ID
