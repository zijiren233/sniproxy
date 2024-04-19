# sniproxy

## 创建需要代理的域名列表 `domains.txt`

- `#` 开头的行为设置此行之后的域名的 IP 地址，用于AdGuardHome的DNS重写

```bash
# 设置域名的IP地址
IPS=192.168.1.1,abcd:ef01:2345:6789:abcd:ef01:2345:6789

# 你也可以使用下面的命令自动获取本机ip地址
# IPS=$(echo `curl -s ifconfig.me -4`,`curl -s ifconfig.me -6`)

cat <<EOF > domains.txt
#$IPS
netflix.com
netflix.net
nflximg.com
nflximg.net
nflxvideo.net
nflxso.net
nflxext.com
hulu.com
huluim.com
hbonow.com
hbogo.com
hbo.com
amazon.com
amazon.co.uk
amazonvideo.com
crackle.com
pandora.com
vudu.com
blinkbox.com
abc.com
fox.com
theplatform.com
nbc.com
nbcuni.com
ip2location.com
pbs.org
warnerbros.com
southpark.cc.com
cbs.com
brightcove.com
cwtv.com
spike.com
go.com
mtv.com
mtvnservices.com
playstation.net
uplynk.com
maxmind.com
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
xboxlive.com
lovefilm.com
turner.com
amctv.com
sho.com
mog.com
wdtvlive.com
beinsportsconnect.tv
beinsportsconnect.net
fig.bbc.co.uk
open.live.bbc.co.uk
sa.bbc.co.uk
www.bbc.co.uk
crunchyroll.com
ifconfig.co
omtrdc.net
sling.com
movetv.com
happyon.jp
abema.tv
hulu.jp
optus.com.au
optusnet.com.au
gamer.com.tw
bahamut.com.tw
hinet.net
dmm.com
dmm.co.jp
dmm-extension.com
dmmapis.com
videomarket.jp
p-smith.com
img.vm-movie.jp
saima.zlzd.xyz
challenges.cloudflare.com
ai.com
openai.com
pay.openai.com
andriod.chat.openai.com
ios.chat.openai.com
chat.openai.com.cdn.cloudflare.net
openaiapi-site.azureedge.net
ios.chat.openai.com.cloudflare.net
chat.openai.com
files.oaiusercontent.com
auth0.openai.com
chatgpt.com
oaiusercontent.com
platform.openai.com
oaistatic.com
aiv-cdn.net
aiv-delivery.net
amazonprimevideo.cn
amazonprimevideo.com.cn
amazonprimevideos.com
amazonvideo.cc
media-amazon.com
prime-video.com
primevideo.cc
primevideo.com
primevideo.info
primevideo.org
primevideo.tv
pv-cdn.net
byteoversea.com
ibytedtos.com
ipstatp.com
muscdn.com
musical.ly
p16-tiktokcdn-com.akamaized.net
byteoversea.com
ibytedtos.com
ibyteimg.com
ipstatp.com
muscdn.com
musical.ly
sgpstatp.com
snssdk.com
tik-tokapi.com
tiktok.com
tiktokcdn.com
tiktokv.com
claude.ai
anthropic.com
cdn.usefathom.com
EOF
```

## 运行服务

```bash
bash run.sh
```

运行后，nginx会监听80和443端口，AdGuardHome会监听53和8080端口，其中53端口为dns端口，8080端口为web管理端口。
