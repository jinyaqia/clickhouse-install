# /bin/bash

# 结果的第一行是密码。 第二行是相应的SHA256哈希

PASSWORD=$1
PASSWORD=$(base64 < /dev/urandom | head -c8); echo "$PASSWORD"; echo -n "$PASSWORD" | sha256sum | tr -d '-'