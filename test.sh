#!/bin/bash


yum install -y wget git openssl

# Disable SELINUX
echo "Disable SELINUX..."
setsebool -P httpd_can_network_connect 1
sed -i 's/enforcing/disabled/g' /etc/selinux/config /etc/selinux/config
setenforce 0
sestatus
echo "Successfully disabled SELINUX"

# Install Java 
echo "____________Installing Java___________"
JAVA_DOWNLOAD_URL=https://javadl.oracle.com/webapps/download/GetFile/1.8.0_281-b09/89d678f2be164786b292527658ca1605/linux-i586/jdk-8u281-linux-x64.rpm
JAVA_BIT_VERSION=x64
JAVA_KEY_VERSION=8u281
JAVA_VERSION=1.8.0_281
cd /tmp

#wget --no-cookies --no-check-certificate --header "Cookie: oraclelicense=accept-securebackup-cookie" https://javadl.oracle.com/webapps/download/AutoDL?BundleId=245049_d3c52aa6bfa54d3ca74e617f18309292
#rpm -ivh --force jdk-8u301-linux-x64.rpm

wget --no-cookies --no-check-certificate --header "Cookie: oraclelicense=accept-securebackup-cookie" "${JAVA_DOWNLOAD_URL}"

if [ -f jdk-${JAVA_KEY_VERSION}-linux-${JAVA_BIT_VERSION}.rpm ]; then
	echo "Installing Java..."
	rpm -ivh --force jdk-${JAVA_KEY_VERSION}-linux-${JAVA_BIT_VERSION}.rpm
	echo "Update environment variables complete"
fi

java -version
echo "Successfully installed Java"

# Install/Configure Jira
#https://confluence.atlassian.com/adminjiraserver/installing-jira-applications-on-linux-from-archive-file-938846844.html

echo "_________Installing Jira___________"
JIRA_VERSION=8.19.0
pushd /tmp >/dev/null

# Create application directory
TARGET_DIR=/opt/atlassian/jira
echo "Creating [${TARGET_DIR}]"
mkdir -p ${TARGET_DIR}

# Download archive
echo "Downloadng archive..."
wget -q -O atlassian-jira-software.tar.gz https://www.atlassian.com/software/jira/downloads/binary/atlassian-jira-software-${JIRA_VERSION}.tar.gz
echo "Completed downloading archive"

echo "Untar archive..."
rm -rf /tmp/jira >/dev/null
mkdir /tmp/jira >/dev/null
tar -xzf atlassian-jira-software.tar.gz -C /tmp/jira --strip 1
cp -R /tmp/jira/* ${TARGET_DIR}
echo "Extracting the Archive successfully Completed"

# Create user

if ! id -u "jira" >/dev/null 2>&1; then
	echo "Create Jira user..."
	/usr/sbin/useradd --create-home --comment "Account for running JIRA Software" --shell /bin/bash jira
	echo "Completed creating Jira user"
else
	echo "Jira user already exists"
fi

# Set installer permissions
echo "Setting permissions..."
chown -R jira ${TARGET_DIR}
chmod -R u=rwx,go-rwx ${TARGET_DIR}
echo "Completed setting permissions"


# Create home directory
echo "Creating home directory..."
HOME_DIR=/var/jirasoftware-home
mkdir -p ${HOME_DIR} >/dev/null
chown -R jira ${HOME_DIR}
chmod -R u=rwx,go-rwx ${HOME_DIR}
echo "Completed creating home directory"

# Set user home for application
echo "Set user home for application..."
echo "export JIRA_HOME=${HOME_DIR}" >>/home/jira/.bash_profile
#echo "export JIRA_OPTS=-Datlassian.darkfeature.jira.onboarding.feature.disabled=true" >>/home/jira/.bash_profile
echo "Completed setting user home for application"


# Create systemd file
# Ref: https://community.atlassian.com/t5/Jira-questions/CentOS-7-systemd-startup-scripts-for-Jira-Fisheye/qaq-p/157575
echo "Create systemd file..."
cat >/usr/lib/systemd/system/jira.service <<EOL
[Unit]
Description=JIRA Service
After=network.target

[Service]
Type=forking
User=jira
Environment=JIRA_HOME=${HOME_DIR}
Environment=JIRA_OPTS=-Datlassian.darkfeature.jira.onboarding.feature.disabled=true
PIDFile=${TARGET_DIR}/work/catalina.pid
ExecStart=${TARGET_DIR}/bin/start-jira.sh
ExecStop=${TARGET_DIR}/bin/stop-jira.sh
ExecReload=${TARGET_DIR}/bin/stop-jira.sh | sleep 60 | /${TARGET_DIR}/bin/start-jira.sh

[Install]
WantedBy=multi-user.target
EOL
echo "Completed creating systemd file"

echo "Enable Jira service..."
systemctl enable jira.service
echo "Completed enabling Jira service"
echo "Starting Jira service..."
systemctl start jira.service
echo "Completed starting Jira service"
echo "Jira service status..."
systemctl status jira.service
echo "Completed Jira status"


echo "Creating database config file in ${HOME_DIR} ..."
# Ref: https://confluence.atlassian.com/adminjiraserver073/connecting-jira-applications-to-sql-server-2014-861253050.html
cat >"${HOME_DIR}/dbconfig.xml" <<EOL
<?xml version="1.0" encoding="UTF-8"?>

<jira-database-config>
  <name>defaultDS</name>
  <delegator-name>default</delegator-name>
  <database-type>postgres72</database-type>
  <schema-name>public</schema-name>
  <jdbc-datasource>
    <url>jdbc:postgresql://postgresservertest0202.postgres.database.azure.com:5432/jiradb</url>
    <driver-class>org.postgresql.Driver</driver-class>
    <username>ibrahimdb@postgresservertest0202</username>
    <password>Ibrah!mTest123</password>
    <pool-min-size>30</pool-min-size>
    <pool-max-size>30</pool-max-size>
    <pool-max-wait>30000</pool-max-wait>
    <validation-query>select 1</validation-query>
    <min-evictable-idle-time-millis>60000</min-evictable-idle-time-millis>
    <time-between-eviction-runs-millis>300000</time-between-eviction-runs-millis>
    <pool-max-idle>30</pool-max-idle>
    <pool-remove-abandoned>true</pool-remove-abandoned>
    <pool-remove-abandoned-timeout>300</pool-remove-abandoned-timeout>
    <pool-test-on-borrow>false</pool-test-on-borrow>
    <pool-test-while-idle>true</pool-test-while-idle>
    <connection-properties>tcpKeepAlive=true;socketTimeout=240</connection-properties>
  </jdbc-datasource>
</jira-database-config>
EOL
ls ${HOME_DIR}
echo "creating database config file in ${HOME_DIR} succeffully completed"

popd >/dev/null
echo "Jira installation is done!"



# Install/Configure Nginx
# https://confluence.atlassian.com/jirakb/integrating-jira-with-nginx-426115340.html
# https://www.digitalocean.com/community/tutorials/how-to-install-nginx-on-centos-7

echo Adding Nginx repository...
yum install -y epel-release

echo Installing Nginx...
yum install -y nginx

# Configure Nginx Sites For
echo "Creating directories..."
mkdir -p /etc/nginx/sites-available
mkdir -p /etc/nginx/sites-enabled
mkdir -p /var/cache/nginx/client_temp
chmod 0777 /var/cache/nginx/client_temp
echo "creating directories is done"

# Update config file
echo "Editing [/etc/nginx/nginx.conf]..."
SEARCH="include \/etc\/nginx\/conf.d\/\*.conf;"
REPLACE="include \/etc\/nginx\/sites-enabled\/\*.conf;"
sed -i -e "s|$SEARCH|$REPLACE|g" /etc/nginx/nginx.conf
sed -i -e "s|        listen       80 default_server;|#        listen       80 default_server;|g" /etc/nginx/nginx.conf
sed -i -e "s|        listen       \[::\]:80 default_server;|#        listen       \[::\]:80 default_server;|g" /etc/nginx/nginx.conf
sed -i -e "s|        server_name  _;|#        server_name  _;|g" /etc/nginx/nginx.conf
sed -i -e "s|        root         /usr/share/nginx/html;|#        root         /usr/share/nginx/html;|g" /etc/nginx/nginx.conf
echo Return Code: $?
echo "Editing [/etc/nginx/nginx.conf] is done"

# Remove contents of /etc/nginx/conf.d
echo "Removing [/etc/nginx/conf.d/*]..."
rm -f /etc/nginx/conf.d/*

# HTTP/S Configuration
SERVER_NAME="localhost"
DNS="jira"
SERVER_PORT="80"
cat >/etc/nginx/sites-available/jira.conf <<EOL

server {
        listen 80 default_server;
        listen [::]:80 default_server;
        server_name localhost;

        client_max_body_size 1G;
        
        location / {
			proxy_set_header Host \$host;
        	proxy_set_header X-Real-IP \$remote_addr;
        	proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        	#proxy_set_header X-Forwarded-Proto "https";
			proxy_set_header X-Forwarded-Proto "http";
            proxy_pass http://localhost:8080/;
        }
}

EOL

# Enable the configuration by creating symbolic link (Incomplete)
ln -sf /etc/nginx/sites-available/jira.conf /etc/nginx/sites-enabled/jira.conf

# Validate nginx configuration file
echo "Validating Nginx confiugration file..."
nginx -t
echo "Nginx confiugration file validation is done"

# Allow http and https ports through firewall
if [ $(systemctl -q is-active firewalld) ]; then
	firewall-cmd --permanent --zone=public --add-service=http
	firewall-cmd --permanent --zone=public --add-service=https
	firewall-cmd --reload
fi

# Restart Nginx
echo "Restarting Nginx service..."
systemctl start nginx
systemctl enable nginx



echo "Executing [$0] complete"

