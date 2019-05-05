#!/usr/bin/env sh


gcloud compute instances list --filter 'labels.machine_type=overpass_update' --uri | xargs gcloud compute instances delete --quiet
