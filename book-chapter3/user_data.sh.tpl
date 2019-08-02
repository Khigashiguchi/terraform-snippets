#!/bin/bash
yum install -y ${package}
systemctl start ${package}.service
