# Hermes Cron Requirements

This directory must provide the necessary tools to be able to create predefined cron jobs on a new hermes installation.

## Configuration

cron jobs should be configurable in a config.yaml file.
configuration should allow for all of the necessary options to fully leverage hermes cron job system.

## Implementation

Create a python script which will deterministically sync (not wipe) the hermes database with the cron jobs as defined in config.yaml.
If the cron jobs already exist - noop.
If the cron jobs exist but are different then are configured - update.
if cron jobs do not exist - insert.

Python script should work regardless of where it is invoked from. 
Python script should find config.yaml by finding where the script path is and looking for a local config.yaml.

