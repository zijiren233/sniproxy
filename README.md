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
- `^` 为 `AdGuardHome` 所用
  - 用于设置AdGuardHome的上游DNS
  - 可以设置多个上游DNS，用 `,` 分隔，如 `^1.1.1.1,2606:4700:4700::1111` 表示使用 `1.1.1.1` 和 `2606:4700:4700::1111` 作为上游DNS
  - 默认为 `h3://dns.google/dns-query,https://dns11.quad9.net/dns-query`
- `$` 为 `AdGuardHome` 所用
  - 用于设置AdGuardHome的admin密码
  - 如果未设置，则默认密码为 `adminadmin`
  - [需要apache2](https://github.com/AdguardTeam/AdGuardHome/wiki/Configuration#password-reset)
    - `apt install apache2-utils`
    - `dnf install httpd-tools`
- `!` 为 `nginx` 所用
  - 用于指定接下来的域名使用的出口IP是 `ipv4` 还是 `ipv6`
  - 也可以使用多个IP，用 `,` 分隔，如 `!1.1.1.1,2606:4700:4700::1111` 表示使用 `1.1.1.1` 和 `2606:4700:4700::1111` 作为出口IP
  - 支持使用网卡名称，格式为 `!device:网卡名称 ipv4/ipv6`，如 `!device:warp ipv4` 表示使用 `warp` 网卡的IPv4地址作为出口IP
    - 可以省略IP版本，默认获取网卡的**所有IP地址**（包括IPv4和IPv6），如 `!device:warp` 会使用 `warp` 网卡的所有IP
    - 指定IP版本只获取对应版本的IP，如 `!device:warp ipv4` 只获取IPv4地址，`!device:warp ipv6` 只获取IPv6地址
    - 可以配置多个网卡，如 `!device:warp ipv4,device:eth0 ipv6`
    - 支持混合配置IP地址和网卡，如 `!1.1.1.1,device:warp ipv4,2.2.2.2`
    - **注意：单独的 `ipv4`/`ipv6` 关键字不能与具体的IP地址或device配置混合使用**
      - ✅ 正确：`!ipv4` 或 `!ipv6` 或 `!1.1.1.1,2.2.2.2` 或 `!device:warp,device:eth0`
      - ❌ 错误：`!ipv4,1.1.1.1` 或 `!ipv6,device:warp`
    - entrypoint会自动监控网卡IP变更，当检测到变更时会自动重新生成配置并重载nginx
  - 如果遇到空行会重置为默认
- `@` 为 `nginx` 所用
  - 定义在每个域名后面，用于指定此域名的源服务器地址
  - 可以是域名或者IP地址
  - 可以定义端口，如果未定义则默认为 `443`
  - 支持端口范围，如 `127.0.0.1:5000-5020` 会展开为 `127.0.0.1:5000` 到 `127.0.0.1:5020` 的所有端口
  - 值会传递给 `upstream` 的 `server`，如果有多个地址，则用 `;` 分隔
  - 如: `netflix.com @127.0.0.1:443` 表示 `netflix.com` 使用 `127.0.0.1:443` 作为上游服务器
  - 如: `netflix.com @1.1.1.1:1000-1005 weight=5; 2.2.2.2 weight=10` 表示 `netflix.com` 使用 `1.1.1.1:1000` 到 `1.1.1.1:1005` 和 `2.2.2.2:443` 作为上游服务器，且权重大小分别为 `5` 和 `10`
  - 更多配置请参考 [nginx upstream](https://nginx.org/en/docs/stream/ngx_stream_upstream_module.html)
  - 也可以定义为 `@` 开头的行，用于指定接下来所有域名使用的源服务器地址
  - 如果遇到空行会重置为默认
- 默认情况下域名使用hostname匹配，如 `github.com` 可以匹配 `api.github.com` 和 `github.com`
  - `=` 开头表示精确匹配
    - 如: `=github.com` 表示精准匹配 `github.com`，无法匹配到 `api.github.com`
  - `*` 开头或结尾表示通配符匹配
    - 如: `*.github.com` 可以匹配 `api.github.com` 但不能匹配 `github.com`
    - 如: `github.*` 可以匹配 `github.com` 和 `github.net`
  - `~` 开头表示正则匹配
    - 如: `~^api\..*\.com$` 可以匹配所有以api开头的.com域名
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
- 对于有空行就重置的配置，如 `!` `@` `<` 等，可以连续两个 `!!` `@@` `<<` 来设置全局默认值，此时遇到空行也会使用全局默认值
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

#### 示例1：使用IP地址

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

#### 示例2：使用网卡名称

前提条件：

- 本地有两个网卡
- `warp` 网卡可以解锁Netflix（使用IPv6）
- `eth0` 网卡可以解锁Disney和TikTok

```txt
// Netflix - 使用warp网卡的IPv6地址
!device:warp ipv6
netflix.com
netflix.net
nflximg.com
nflximg.net
nflxvideo.net
nflxso.net
nflxext.com

// Disney - 使用eth0网卡的IPv4地址
!device:eth0 ipv4
disney.com
disneyjunior.com
disneyplus.com
disneystreaming.com

// TikTok - 使用eth0网卡的所有IP地址（IPv4和IPv6）
!device:eth0
tiktok.com
tiktokcdn.com
tiktokv.com
```

## 运行服务

```bash
# 直接运行会使用ipv4或ipv6请求代理域名，取决于linux优先级配置
bash run.sh

# 如果默认使用绑定ip请求代理域名
bash run.sh -b <ip>

# 默认绑定443端口，如果要绑定其他端口或多个端口，则使用 -p 参数
bash run.sh -p <port1>,<port2> -p <port3>

# 如果你修改了domains.txt文件，需要重新启动服务

# 如果只想启动sniproxy服务，使用指定dns，不想启动AdGuardHome服务
bash run.sh -d 1.1.1.1 nginx

# 如果只想启动AdGuardHome服务，不想启动sniproxy服务
bash run.sh adguardhome
```

运行后，nginx会监听80和443端口，AdGuardHome会监听53和8080端口，其中53端口为dns端口，`8080` 端口为web管理端口。

把服务器的dns设置为AdGuardHome的IP地址，这样就可以实现通过AdGuardHome的DNS重写来解锁Netflix、Disney和TikTok。

其中，AdGuardHome的 `8080` 端口还可以当作 `doh(dns over http)` ，注意并不是 `dns over https`

如果要启用 `doh(dns over https)` 建议使用反向代理或cloudflare的cdn
