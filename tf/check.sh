#!/usr/bin/env bash

curdir=$(eval pwd)
modules=("tf/setup" "tf/infra")

for module in ${modules[@]}
do
  module_folder=$curdir/$module
  echo "buidling terraform module $module_folder"
  cd $module_folder
  terraform init
  terraform validate
  terraform plan -detailed-exitcode -out=tf.plan
  rm tf.plan
done
