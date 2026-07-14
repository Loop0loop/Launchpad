#!/bin/sh
set -eu

exec swift run LaunchpadPackager app --variant development
