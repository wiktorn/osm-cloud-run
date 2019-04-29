#!/usr/bin/env sh

apt update
apt upgrade -y
apt install -y docker.io google-cloud-sdk git

(
    set -e


    docker run --name overpass_step1 \
        -e OVERPASS_META=yes \
        -e OVERPASS_MODE=init \
        -e OVERPASS_PLANET_URL=http://download.geofabrik.de/europe/monaco-latest.osm.bz2 \
        -e OVERPASS_DIFF_URL=http://download.geofabrik.de/europe/monaco-updates/ \
        -e OVERPASS_COMPRESSION=lz4 \
        -i \
        wiktorn/overpass-api \
        /bin/bash -c '/app/docker-entrypoint.sh && /app/bin/update_overpass.sh && /app/bin/osm3s_query --progress --rules --rules --db-dir=/db/db < /db/db/rules/areas.osm3s'

    mkdir /app
    cd /app
    git clone https://github.com/wiktorn/osm-cloud-run.git
    cd osm-cloud-run/overpass/init
    docker cp supervisord.conf overpass_step1:/etc/supervisor/supervisord.conf
    docker commit --change 'CMD /app/docker-entrypoint.sh' overpass_step1 gcr.io/osm-vink/overpass-poland:latest
    gcloud auth configure-docker -q
    gcloud docker -- push gcr.io/osm-vink/overpass-poland:latest
    gcloud beta run deploy overpass-poland \
        --image=gcr.io/osm-vink/overpass-poland:latest \
        --region=us-central1 \
        --memory=1024Mi \
        --allow-unauthenticated
) | gsutil cp - gs://vink-osm-startup-scripts-us/overpass/init.log

gcloud compute instances list --filter 'labels.machine_type=overpass' --uri | xargs gcloud compute instances delete --quiet

