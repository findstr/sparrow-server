# Etcd中key的分布情况
----

### 一些全局配置（如密码，sercert之类）
`/conf/db/username`	数据库账号
`/conf/db/password`	数据库密码

### 分布式锁(用于分配gateway的惟一workerid)
`/lock/${service}/${listen}`

### 所有服务的workerid->监听端口
`/service/db/capacity`			数据库实例个数
`/service/db/instance/${instanceid}`	数据库实例的端口


