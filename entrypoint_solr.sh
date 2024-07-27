bash -l -c "./bin/solr start -f -p 8983 -h 0.0.0.0"
bash -l -c "sleep 20"
bash -l -c "./bin/solr create -c 'blacklight-core' -d ./solr/conf"
