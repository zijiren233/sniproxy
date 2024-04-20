# sniproxy

## 创建需要代理的域名列表 `domains.txt` 以及设置这些域名解析到的IP地址（解锁机的IP）

- `domains.txt.example` 为示例文件，可以参考此文件创建 `domains.txt`
- `#` 开头的行为设置此行之后的域名的 IP 地址，用于AdGuardHome的DNS重写
- 可以重复定义 `#` 行用来设置此行之后的域名的 IP 地址
- 多个IP用 `,` 分隔，如 `1.1.1.1,2606:4700:4700::1111`
- 可以通过 `echo $(curl -s ifconfig.me -4),$(curl -s ifconfig.me -6)` 命令获取本机的IP地址
- 可以使用 `//` 开头的行来注释，此行不会被解析

### `domains.txt` 示例

前提条件：

- 有两台服务器，第一台服务器的IP地址为 `1.1.1.1,2606:4700:4700::1111`，第二台服务器的IP地址为 `1.0.0.1,2606:4700:4700::1001`
- 第一台服务器解锁Netflix，第二台服务器解锁Disney和TikTok

```txt
#1.1.1.1,2606:4700:4700::1111

// Netflix
netflix.com
netflix.net
nflximg.com
nflximg.net
nflxvideo.net
nflxso.net
nflxext.com

#1.0.0.1,2606:4700:4700::1001

// Disney
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
# 直接运行会使用ipv4和ipv6请求代理域名
bash run.sh

# 如果只使用ipv4请求代理域名
bash run.sh -4

# 如果只使用ipv6请求代理域名
bash run.sh -6

# 如果使用绑定ip请求代理域名
bash run.sh -b <ip>

# 如果你修改了domains.txt文件，需要重新加载配置
# 也需要指定 -4 -6 -b 等参数，如 bash gen.sh -4
bash gen.sh && docker compose restart
```

运行后，nginx会监听80和443端口，AdGuardHome会监听53和8080端口，其中53端口为dns端口，8080端口为web管理端口。

把服务器的dns设置为AdGuardHome的IP地址，这样就可以实现通过AdGuardHome的DNS重写来解锁Netflix、Disney和TikTok。
