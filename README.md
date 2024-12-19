# sniproxy

## 创建需要代理的域名列表 `domains.txt` 以及设置这些域名解析到的IP地址（解锁机的IP）

- `domains.txt.example` 为示例文件，可以参考此文件创建 `domains.txt`
- `//` 开头的行用来注释，此行不会被解析
- `#` 为 `AdGuardHome` 所用
  - 用于AdGuardHome的DNS重写
  - `#` 开头的行为设置此行之后的域名解析到的 IP 地址
  - 可以重复定义 `#` 行，用来设置此行之后的域名的 IP 地址
  - 多个IP用 `,` 分隔，如 `1.1.1.1,2606:4700:4700::1111`
  - 可以通过 `echo $(curl -s ifconfig.me -4),$(curl -s ifconfig.me -6)` 命令获取本机的IP地址
- `!` 为 `nginx` 所用
  - 用于指定接下来的域名使用的IP是 `ipv4` 还是 `ipv6`
  - 如果遇到空行会重置为默认
- `@` 为 `nginx` 所用
  - 定义在每个域名后面，用于指定此域名的源服务器地址
  - 可以是域名或者IP地址
  - 可以定义端口，如果未定义则默认为 `443`
  - 值会传递给 `upstream` 的 `server`，如果有多个地址，则用 `,` 分隔
  - 如: `netflix.com @127.0.0.1:443` 表示 `netflix.com` 使用 `127.0.0.1:443` 作为上游服务器
  - 如: `netflix.com @1.1.1.1 weight=5, 2.2.2.2 weight=10` 表示 `netflix.com` 使用 `1.1.1.1:443` 和 `2.2.2.2:443` 作为上游服务器，且权重大小分别为 `5` 和 `10`
  - 更多配置请参考 [nginx upstream](https://nginx.org/en/docs/stream/ngx_stream_upstream_module.html)
- `=` 为 `nginx` 所用
  - 用于指定当前域名不使用后缀匹配，而是精准匹配
  - 如: `=github.com` 表示精准匹配 `github.com`，无法匹配到 `api.github.com`
- `<` 为 `nginx` 所用
  - 用于指定接下来的域名的速率
  - 如果遇到空行会重置为默认
  - 值会传递给 `proxy_download_rate` 和 `proxy_upload_rate`
  - 如: `<1k` 表示下载和上传速率限制为 `1k`
- `&` 为 `nginx` 所用
  - 用于指定全局允许的ip白名单
  - 如果没有设置，则默认允许所有ip
  - 值会传递给 `allow`，且最后会附加一个 `deny all`
  - 允许配置多个 `&` 行，每行内可以有多个IP，用 `,` 分隔
  - 如: `&1.1.1.1,2606:4700:4700::1111` 表示只允许 `1.1.1.1` 和 `2606:4700:4700::1111` 访问
- `` ` `` 和 `` ``` `` 为 `nginx` 所用
  - 用于指定代码块到 `stream` 模块中
  - 比如：

````txt
` server { listen 22; proxy_pass github.com:22; } `

```
server { 
    listen 22; 
    proxy_pass github.com:22; 
}
```
````

### `domains.txt` 示例

前提条件：

- 有两台服务器
- 第一台服务器的IP地址为 `1.1.1.1,2606:4700:4700::1111`
  - 第一台服务器解锁Netflix
  - 且只有ipv6解锁Netflix
- 第二台服务器的IP地址为 `1.0.0.1,2606:4700:4700::1001,2606:4700:4700::1002`
  - 第二台服务器解锁Disney和TikTok
  - 且只有`2606:4700:4700::1002`解锁Disney

```txt
#1.1.1.1,2606:4700:4700::1111

// Netflix
!ipv6
netflix.com
netflix.net
nflximg.com
nflximg.net
nflxvideo.net
nflxso.net
nflxext.com

#1.0.0.1,2606:4700:4700::1001

// Disney
!2606:4700:4700::1002
disney.com
disneyjunior.com
adobedtm.com
bam.nr-data.net
bamgrid.com
braze.com
cdn.optimizely.com
cdn.registerdisney.go.com
cws.conviva.com
d9.flashtalking.com
disney-plus.net
disney-portal.my.onetrust.com
disney.demdex.net
disney.my.sentry.io
disneyplus.bn5x.net
disneyplus.com
disneyplus.com.ssl.sc.omtrdc.net
disneystreaming.com
dssott.com
execute-api.us-east-1.amazonaws.com
js-agent.newrelic.com

// TikTok
byteoversea.com
ibytedtos.com
ipstatp.com
muscdn.com
musical.ly
p16-tiktokcdn-com.akamaized.net
ibyteimg.com
sgpstatp.com
snssdk.com
tik-tokapi.com
tiktok.com
tiktokcdn.com
tiktokv.com
```

## 运行服务

```bash
# 直接运行会使用ipv4或ipv6请求代理域名，取决于linux优先级配置
bash run.sh

# 如果默认使用ipv4请求代理域名
bash run.sh -4

# 如果默认使用ipv6请求代理域名
bash run.sh -6

# 如果默认使用绑定ip请求代理域名
bash run.sh -b <ip>

# 如果你修改了domains.txt文件，需要重新启动服务
# 也需要指定 -4 -6 -b 等参数，如 bash run.sh -4
bash run.sh

# 如果只想启动sniproxy服务，使用指定dns，不想启动AdGuardHome服务
bash run.sh -d 1.1.1.1 nginx

# 如果只想启动AdGuardHome服务，不想启动sniproxy服务
bash run.sh adguardhome
```

运行后，nginx会监听80和443端口，AdGuardHome会监听53和8080端口，其中53端口为dns端口，`8080` 端口为web管理端口。

把服务器的dns设置为AdGuardHome的IP地址，这样就可以实现通过AdGuardHome的DNS重写来解锁Netflix、Disney和TikTok。

其中，AdGuardHome的 `8080` 端口还可以当作 `doh(dns over http)` ，注意并不是 `dns over https`

如果要启用 `doh(dns over https)` 建议使用反向代理或cloudflare的cdn
