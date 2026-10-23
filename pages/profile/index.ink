<script def>
{
  "navigationBarTitleText": "客户档案"
}
</script>

<script setup>
// 客户社媒档案 + 风险预警：说公司名 → 后端聚合档案 → 屏显风险等级与要点
// 档案数据由后端确定性生成（同一公司结果稳定），AI 不编造
export default {
  data: {
    apiBase: 'http://192.168.1.100:8000',
    state: 'idle',       // idle | listening | loading | done | error
    heard: '',
    p: null,             // 档案 { company, level, levelText, socials[], risks[], advice }
    errMsg: '',
  },
  session: null,

  onUnload() { if (this.session) { try { this.session.abort(); } catch (e) {} } },

  onKeyDown(event) {
    if (event.code === 'Enter' && (this.data.state === 'idle' || this.data.state === 'done')) this.startListen();
  },
  tapStart() { this.startListen(); },

  startListen() {
    if (this.session) { try { this.session.abort(); } catch (e) {} }
    this.setData({ state: 'listening', heard: '', p: null, errMsg: '' });
    const rec = new SpeechRecognition();
    this.session = rec;
    rec.lang = 'zh-CN';
    rec.interimResults = true;  // 边说边显示，降低感知延迟
    rec.onresult = (event) => {
      const res = event.results;
      if (!res || !res.length) return;
      const last = res[res.length - 1];
      const text = (last && last[0] && last[0].transcript) || '';
      if (!text) return;
      this.setData({ heard: text, state: 'loading' });
      this.load(text);
    };
    rec.onerror = (event) => this.setData({ state: 'error', errMsg: '识别失败：' + (event.error || '') });
    rec.onend = () => { this.session = null; };
    try { rec.start(); } catch (e) { this.setData({ state: 'error', errMsg: '无法启动麦克风' }); }
  },

  load(name) {
    fetch(this.data.apiBase + '/api/profile?name=' + encodeURIComponent(name))
      .then((r) => r.json())
      .then((d) => {
        this.setData({ p: d, state: 'done' });
        try { speechSynthesis.speak(new SpeechSynthesisUtterance(d.levelText + '。' + d.advice), 'enqueue'); } catch (e) {}
      })
      .catch(() => this.setData({ state: 'error', errMsg: '查不到档案，检查后端连接' }));
  },

  stateText(s) {
    return { idle: '按确认键说公司名', listening: '请说公司名…', loading: '查询中…',
             done: '档案如下', error: '出错了' }[s] || '';
  },
};
</script>

<page>
  <view class="page">
    <text class="state">{{stateText(state)}}</text>
    <text class="heard" wx:if="{{heard}}">「{{heard}}」</text>

    <block wx:if="{{p}}">
      <text class="co">{{p.company}}</text>
      <text class="lv">{{p.levelText}}</text>
      <text class="sec">社媒档案</text>
      <text class="row" wx:for="{{p.socials}}" wx:key="k">{{item.k}}：{{item.v}}</text>
      <text class="sec">风险预警</text>
      <text class="risk" wx:for="{{p.risks}}" wx:key="*this">⚠ {{item}}</text>
      <text class="adv">{{p.advice}}</text>
    </block>

    <text class="err" wx:if="{{errMsg}}">{{errMsg}}</text>
    <text class="go" bindtap="tapStart">▶ 重新查询</text>
  </view>
</page>

<style>
.page { width: 100%; height: 100%; display: flex; flex-direction: column;
        padding: 12px 18px; background: #000; color: #0f0; }
.state { font-size: 13px; font-weight: bold; margin-bottom: 6px; }
.heard { font-size: 12px; color: #7f7; margin-bottom: 4px; }
.co { font-size: 15px; font-weight: bold; }
.lv { font-size: 13px; color: #ff0; margin: 2px 0 6px; }
.sec { font-size: 11px; color: #4a4; margin: 5px 0 2px; }
.row { font-size: 11px; line-height: 1.55; color: #af9; }
.risk { font-size: 11px; line-height: 1.55; color: #f90; }
.adv { font-size: 12px; color: #0f0; margin-top: 5px; line-height: 1.45; }
.err { font-size: 11px; color: #f66; }
.go { font-size: 12px; border: 1px solid #0f0; border-radius: 6px;
      padding: 4px 10px; align-self: flex-start; margin-top: 6px; }
</style>
