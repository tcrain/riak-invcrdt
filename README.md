# InvCRDT for Rika Experiment
============

The aim of this experiment is to analyze the performance and consistency of an always decreasing counter using different deployments in Riak.

Here is a list of useful commands to configure Erlang, Riak and test our experiment on Amazon EC2.

# 1 - Install Erlang

sudo yum install gcc glibc-devel make ncurses-devel openssl-devel autoconf java-1.6.0-openjdk-devel.x86_64

wget http://www.erlang.org/download/otp_src_R16B02.tar.gz

tar -xvf otp_src_R16B02.tar.gz

cd otp_src_R16B02

./configure

make

sudo make install

# 2 - Install Riak

sudo yum install gcc gcc-c++ glibc-devel make git pam-devel

git clone https://github.com/basho/riak

cd riak

make rel

mv rel/riak ..

# 3 - Increase maximum file handlers in CentOS
sudo vi /etc/sysctl.conf		add line: fs.file-max = 512000

sudo sysctl -p

/etc/security/limits.conf 		add line: * - nofile 65535

ulimit -n 65535

# 4 - Create the Strong Consistency Bucket

cd ../riak/bin

./riak-admin bucket-type create STRONG '{"props": {"consistent":true,}}'

./riak-admin bucket-type activate STRONG

#Create the cluster

./riak-admin cluster join riak@ADDRESS

./riak-admin cluster plan

./riak-admin cluster commit

#Add a pre-/post-commit hook using HTTP interface
curl -XPUT -H "Content-Type: application/json" http://127.0.0.1:8098/buckets/buck/props -d '{"props":{"precommit":[{"mod": "MODULE", "fun": "FUNCTION"}]}}'

#Check Bucket properties

curl localhost:8098/buckets/messages/props | python -mjson.tool


##Clear Riak Cluster



###Test CRDT version
worker_sc:reset_crdt(100,{<<"STRONG">>,<<"ITEMS">>},site1,["127.0.0.1","127.0.0.1"],[site2]).

Stats = client_stats:start(1,100).

worker_sc:start(init, 1, 0, Stats, "127.0.0.1", {<<"STRONG">>,<<"ITEMS">>},site1).

{ok, Pid} = riakc_pb_socket:start_link("127.0.0.1", 8087).

{ok,Obj}=riakc_pb_socket:get(Pid, {<<"STRONG">>,<<"ITEMS">>}, <<"KEY">>, [],5000).

nncounter:from_binary(riakc_obj:get_value(Obj)).

###Run e-script
./scripts/script localhost site0 1 100 /Users/balegas/workspace/riak-invcrdt/ site ITEMS STRONG true 127.0.0.1 localhost

##Copy worker dir to remote host
rsync --exclude '*.git' --exclude 'riak-erlang-client' riak-invcrdt HOST:~




