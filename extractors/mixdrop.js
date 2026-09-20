// Mixdrop embed extractor (mixdrop.co, mixdrop.to, mixdrop.ag, mixdrop.is, etc.)
// Unpacks Dean Edwards packer to extract direct wurl / MDCore.wurl MP4 links.

var MIXDROP_UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

function getInfo() {
  return {
    id: 'mixdrop',
    name: 'Mixdrop',
    version: '1.0.0',
    hosts: [
      'mixdrop.co',
      'mixdrop.to',
      'mixdrop.ag',
      'mixdrop.is',
      'mixdrop.bz',
      'mixdrop.ch',
      'mixdrop.top',
      'mixdrop.sx',
      'mixdrop.vc',
      'mixdrop.cat',
      'mixdrop.ps',
      'mixdrop.ai',
      'mixdrop.club',
      'mixdrop.si',
      'mixdrop.net'
    ]
  };
}

function _parse(html, hostUrl) {
  var js = html;
  var pk = html.match(/(eval\(function\(p,a,c,k,e,d\)[\s\S]*?\.split\('\|'\),0,\{\}\)\))/);
  if (pk && typeof unpackJs === 'function') {
    js = unpackJs(pk[1]);
  }

  var match = js.match(/(?:MDCore\.wurl|MDCore\.vurl|wurl|vurl)\s*=\s*["']([^"']+)["']/) ||
              js.match(/src\s*:\s*["']([^"']+)["']/);

  if (!match) return null;
  var streamUrl = match[1];
  if (streamUrl.indexOf('//') === 0) {
    streamUrl = 'https:' + streamUrl;
  }

  var host = hostUrl || 'https://mixdrop.ag/';
  if (host.indexOf('http') !== 0) host = 'https://' + host;
  if (host.slice(-1) !== '/') host += '/';

  return {
    url: streamUrl,
    quality: '1080p',
    container: 'mp4',
    headers: {
      'Referer': host,
      'User-Agent': MIXDROP_UA
    },
    kind: 'sub',
    audioLang: 'ja',
    subtitles: []
  };
}
globalThis.__mixdropParse = _parse;

function extract(url, opts) {
  opts = opts || {};
  var _kind = opts.kind || 'sub';
  var _lang = opts.audioLang || (_kind === 'dub' ? 'en' : 'ja');
  var embed = String(url).replace('/f/', '/e/');
  var mHost = embed.match(/^(https?:\/\/[^\/]+)/);
  var hostOrigin = mHost ? mHost[1] + '/' : 'https://mixdrop.ag/';

  var headers = {
    'Referer': hostOrigin,
    'User-Agent': MIXDROP_UA
  };

  return fetch(embed, { headers: headers }).then(function (r) {
    var s = _parse(r.body || '', hostOrigin);
    if (!s) throw new Error('mixdrop: no playable source found');
    return [s];
  }).then(function (arr) {
    return arr.map(function (s) {
      s.kind = _kind;
      s.audioLang = _lang;
      return s;
    });
  });
}
