#!/bin/sh

. /etc/sysconfig/heat-params

YAML_CONFIG_DIR=/etc/kubernetes/config
mkdir -p ${YAML_CONFIG_DIR}

cat > ${YAML_CONFIG_DIR}/encryption-config.yaml <<EOF
kind: EncryptionConfig
apiVersion: v1
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: ${ENCRYPTION_KEY}
      - identity: {}
EOF
