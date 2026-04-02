# 百度完整流程记录

最后更新：2026-04-02

这份文档只描述百度从授权到拿到视频列表，再到请求播放并开始播放的完整流程。

不写代码实现，不写播放器内部处理，只写：

- 用户做了什么
- App 拿什么去请求
- 百度返回什么
- 下一步继续拿什么去请求

## 1. 用户做百度授权

### 第一步：打开百度授权页

用户在 app 里点“登录百度网盘”后，app 会打开百度 OAuth 授权页面。

请求：

```text
GET https://openapi.baidu.com/oauth/2.0/authorize
```

参数：

- `response_type=code`
- `client_id=<百度开放平台分配的 client_id>`
- `redirect_uri=bdconnect://oauth`
- `scope=basic netdisk`
- `display=touch`
- `locale=zh_CN`

这一步的目的：

- 让用户在百度侧登录
- 让百度给 app 一个授权码 `code`

### 第二步：百度回跳给 app

用户同意授权后，百度会跳回 app：

```text
bdconnect://oauth?code=<authorization_code>
```

这一步 app 真正拿到的东西：

- `code`

### 第三步：用 code 换 token

拿到 `code` 后，app 再请求百度 token 接口。

请求：

```text
POST https://openapi.baidu.com/oauth/2.0/token
Content-Type: application/x-www-form-urlencoded
```

表单参数：

- `grant_type=authorization_code`
- `code=<authorization_code>`
- `client_id=<client_id>`
- `client_secret=<client_secret>`
- `redirect_uri=bdconnect://oauth`

百度返回 JSON，主要字段：

- `access_token`
- `refresh_token`
- `expires_in`
- `token_type`

这一步 app 真正拿到的东西：

- `access_token`
- `refresh_token`

后面所有百度目录扫描和播放请求，核心都靠这个 `access_token`。

## 2. 用户选择百度里的目录

如果用户打开“选择文件夹”，app 会去请求百度目录列表。

请求：

```text
GET https://pan.baidu.com/rest/2.0/xpan/file
```

参数：

- `method=list`
- `access_token=<access_token>`
- `dir=<当前目录路径>`
- `start=<分页起点>`
- `limit=100`
- `order=name`
- `folder=1`

百度返回 JSON，主要字段：

- `list`

`list` 每项里常见字段：

- `fs_id`
- `path`
- `server_filename`
- `isdir`

这一步 app 真正拿到的东西：

- 当前目录下的子文件夹列表
- 每个子文件夹的 `path`

用户最终会选定一个根目录，例如：

- `/`
- `/我的资源`
- `/某个动画目录`

后面扫描视频列表时，就从这个目录开始。

## 3. 请求视频列表

用户点“扫描”后，app 会从选定目录开始递归请求百度目录接口。

请求：

```text
GET https://pan.baidu.com/rest/2.0/xpan/file
```

参数：

- `method=list`
- `access_token=<access_token>`
- `dir=<当前扫描目录>`
- `start=<分页起点>`
- `limit=1000`
- `order=name`

百度返回 JSON，主要字段：

- `errno`
- `list`

`list` 每项常见字段：

- `fs_id`
- `path`
- `server_filename`
- `size`
- `isdir`

处理规则：

- `isdir == 1`：说明是目录，继续递归请求这个目录
- `isdir == 0`：说明是文件
- 只有扩展名属于视频的文件才会进入视频列表

最后 app 拿到的视频数据，核心字段就是：

- `title`
- `remotePath`
- `remoteItemId`
- `fileSize`

其中：

- `title` 来自文件名
- `remotePath` 来自百度返回的 `path`
- `remoteItemId` 来自百度返回的 `fs_id`

## 4. 以当前两个视频为例，扫描结果是什么

当前两个真实样例视频：

```json
[
  {
    "title": "公視啊設計第01集",
    "remotePath": "/公視啊設計第01集.mp4",
    "remoteItemId": "113435344869342",
    "fileSize": 213053992
  },
  {
    "title": "打工人在喵厂 V6 0531 交播版",
    "remotePath": "/打工人在喵厂 V6 0531 交播版.MP4",
    "remoteItemId": "548410626013908",
    "fileSize": 381167460
  }
]
```

也就是说，到了“点播放”这一步，app 手里至少已经有：

- `access_token`
- `remotePath`
- `remoteItemId`

真正发起播放请求时，当前链路主要用的是：

- `access_token`
- `remotePath`

## 5. 用户点播放后的第一步：请求播放入口元数据

用户点某个视频播放后，app 先请求百度的 `streaming` 接口。

基础请求：

```text
GET https://pan.baidu.com/rest/2.0/xpan/file?method=streaming&access_token=<access_token>&path=<remotePath>&type=M3U8_AUTO_720
```

但第一步并不是直接拿 m3u8，而是在这个基础上再加：

- `nom3u8=1`

所以第一步真实请求长这样：

```text
GET https://pan.baidu.com/rest/2.0/xpan/file?method=streaming&access_token=<access_token>&path=<remotePath>&type=M3U8_AUTO_720&nom3u8=1
```

请求头里会带常见浏览器/网页相关信息，这一步百度不是直接回 m3u8，而是先回 JSON。

百度这一步返回的 JSON，常见字段：

- `errno`
- `error_code`
- `request_id`
- `adTime`
- `adToken`
- `ltime`

这一步 app 真正拿到的关键数据：

- `adToken`
- `adTime`
- `ltime`

这说明：

- 百度播放入口不是一个拿到就能直接播的稳定 m3u8
- 它先给你一组状态数据，再让你继续请求

## 6. 真实 JSON 返回样例

当前真实抓到过的一个返回样例如下：

```json
{"errno":133,"request_id":9038908558792887754,"adTime":8,"adToken":"a5OmDbpdn38BzrNRnsGB7YgjbTij3dlP51uFuitrWQXKaOIxBoXbVjicV8oBHtlPS0+ObKXVogPNiFeziDAUub0KhIJ5sXVNBNKg3fP5+fQH9HJv+8R1DIC02H04Ht7BJdVZtjeDDJ4Vuy9uV7rlmDVHRm64YKf8q5L18uF17H1g=","ltime":5}
```

从这个样例可以直接看到：

- `errno=133`
- `adToken` 是一个很长的动态字符串
- `adTime=8`
- `ltime=5`

这一步的含义就是：

- 现在还没有直接给你 m3u8
- 先等
- 然后用 `adToken` 再去请求

## 7. 第二步：拿真正的 m3u8

等完之后，app 再次请求同一个 `streaming` 接口，但这次会把 `adToken` 带上。

请求形式：

```text
GET https://pan.baidu.com/rest/2.0/xpan/file?method=streaming&access_token=<access_token>&path=<remotePath>&type=M3U8_AUTO_720&adToken=<adToken>
```

百度这一步有两种可能：

1. 直接返回真正的 m3u8 文本
2. 继续返回 JSON，比如继续 `errno=133`

如果又回了 `133`，说明还要继续等，或者 `adToken` 已经刷新了。

也就是说，这一阶段的真实情况是：

- app 可能要反复请求多次
- 中间每次都可能拿到新的 `adToken`
- 最终才会拿到真正的 m3u8

## 8. 两个视频实际的播放入口请求

### 8.1 公視啊設計第01集

基础播放请求：

```text
https://pan.baidu.com/rest/2.0/xpan/file?method=streaming&access_token=121.e9d3f14f8beacef7984310c0a5b3a007.Y5VVM4Up7IaMiobsxEXbX00_GrBXR_pui8Aijgp.2T2ohg&path=%2F%E5%85%AC%E8%A6%96%E5%95%8A%E8%A8%AD%E8%A8%88%E7%AC%AC01%E9%9B%86.mp4&type=M3U8_AUTO_720
```

第一步 step1 请求：

```text
https://pan.baidu.com/rest/2.0/xpan/file?method=streaming&access_token=121.e9d3f14f8beacef7984310c0a5b3a007.Y5VVM4Up7IaMiobsxEXbX00_GrBXR_pui8Aijgp.2T2ohg&path=%2F%E5%85%AC%E8%A6%96%E5%95%8A%E8%A8%AD%E8%A8%88%E7%AC%AC01%E9%9B%86.mp4&type=M3U8_AUTO_720&nom3u8=1
```

### 8.2 打工人在喵厂 V6 0531 交播版

基础播放请求：

```text
https://pan.baidu.com/rest/2.0/xpan/file?method=streaming&access_token=121.e9d3f14f8beacef7984310c0a5b3a007.Y5VVM4Up7IaMiobsxEXbX00_GrBXR_pui8Aijgp.2T2ohg&path=%2F%E6%89%93%E5%B7%A5%E4%BA%BA%E5%9C%A8%E5%96%B5%E5%8E%82%20V6%200531%20%E4%BA%A4%E6%92%AD%E7%89%88.MP4&type=M3U8_AUTO_720
```

第一步 step1 请求：

```text
https://pan.baidu.com/rest/2.0/xpan/file?method=streaming&access_token=121.e9d3f14f8beacef7984310c0a5b3a007.Y5VVM4Up7IaMiobsxEXbX00_GrBXR_pui8Aijgp.2T2ohg&path=%2F%E6%89%93%E5%B7%A5%E4%BA%BA%E5%9C%A8%E5%96%B5%E5%8E%82%20V6%200531%20%E4%BA%A4%E6%92%AD%E7%89%88.MP4&type=M3U8_AUTO_720&nom3u8=1
```

## 9. 拿到 m3u8 后，里面是什么

真正拿到 m3u8 后，里面最核心的内容就是一组片段地址。

这些片段地址不是干净短链接，而是非常重的动态 URL，里面会带很多参数，比如：

- `fsid`
- `sign`
- `xcode`
- `time`
- `range`
- `len`
- `etag`
- `fid`
- `slice_md5`
- `backhost`
- `dtime`
- `pmk`

也就是说：

- m3u8 不是“几个普通文件 URL”
- 而是一串已经带签名和播放上下文的片段地址

## 10. 两个视频真实的片段情况

### 10.1 公視啊設計第01集

当前样例里，这条视频的 m3u8 解析结果是：

- `segmentCount = 91`

前面的 URL 家族是：

- `_7795_1_ts`

后面切到了：

- `_7795_4_ts`

前 3 个片段的时长：

- `10s`
- `10s`
- `10s`

最后 2 个片段的时长：

- `10s`
- `8s`

### 10.2 打工人在喵厂 V6 0531 交播版

当前样例里，这条视频的 m3u8 解析结果是：

- `segmentCount = 38`

前面的 URL 家族是：

- `_7475_1_ts`

后面切到了：

- `_7475_3_ts`

前 3 个片段的时长：

- `2s`
- `2s`
- `2s`

最后 2 个片段的时长：

- `10s`
- `7s`

## 11. segment 请求后实际回来的是什么

当 app 去请求 m3u8 里的 segment URL 时，百度返回的已经不是 JSON，而是媒体数据本体。

当前两个真实样例里，从实际抓到的 payload 看，里面出现过这些标记：

- `moov`
- `mdat`
- `hev1`
- `hvcC`
- `mp4a`

这说明当前这两个样例里，百度实际返回的片段更像：

- `MP4/fMP4` 风格的小片段

而不是：

- 很纯粹的原生 `MPEG-TS` 文件

## 12. 从头到尾压缩成一句话

整个流程就是：

1. 用户登录百度，拿到 `code`
2. 用 `code` 换 `access_token / refresh_token`
3. 用 `access_token` 请求目录列表
4. 从目录列表里拿到视频的 `remotePath / remoteItemId / fileSize`
5. 用户点播放后，用 `access_token + remotePath` 请求 `streaming`
6. 第一步先拿 `adToken / adTime / ltime`
7. 第二步再带 `adToken` 去请求真正的 m3u8
8. m3u8 里再给出一串带签名的 segment URL
9. 请求这些 segment URL，百度返回真正的媒体片段数据

## 13. 这些观察对客户端意味着什么

基于前面的真实样例，至少可以得到下面这些结论：

- 客户端不能把百度播放理解成“拿到一个固定 m3u8 就结束了”。
- `streaming` 入口本身就是有状态的，请求一次不一定直接拿到 m3u8。
- `adToken`、`adTime`、`ltime` 说明播放入口前面还有一层百度自己的等待和控制逻辑。
- m3u8 里的片段 URL 不是普通静态文件地址，而是带大量签名和上下文参数的动态地址。
- 同一条视频内部，片段 URL 的路径家族也可能变化，说明前后片段不一定来自完全同一组底层资源。
- 片段 URL 看起来像 `_ts`，但当前样例里实际下回来的 payload 更像 `MP4/fMP4` 风格的小片段，而不是最朴素、最标准的原生 `.ts`。

这些现象意味着：

- 客户端不能只做“把百度返回内容原样扔给播放器”这么简单的事情。
- 客户端需要自己理解播放入口、m3u8、segment URL 和实际 payload 之间的差异。
- 后续开发时，不能假设“URL 长得像 ts，内容就一定是标准 ts”。
- 也不能假设“同一条视频的所有 segment 都是完全同质的”。

简短说：

- 百度这条播放链路不是一个特别干净、特别标准、特别适合播放器直接生吃的输入源。
- 对客户端来说，真正重要的是把百度侧这套返回，稳定地整理成一个播放器更容易消费的连续输入。
