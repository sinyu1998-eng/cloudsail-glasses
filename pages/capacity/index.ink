<script def>
{
  "navigationBarTitleText": "产能与报价"
}
</script>

<script setup>
// 产线工人/业务员双场景：
// - 口述产量（"3号线今天做到1200件"）→ 结构化 → 回传看板
// - 输入成本 → 后端算三档报价 + 交期（确定性计算，AI 不碰数字）
import { LanguageModel } from 'language-model';

export default {
  data: {
    apiBase: 'http://192.168.1.100:8000',
    mode: 'capacity',        // capacity | quote
    capacity: null,          // 后端产能数据
    heard: '',
    report: null,            // 口述回传结果
    quote: null,             // 报价结果
    err: '',
  },

  session: null,

  onReady() {
    this.loadCapacity();
  },

  onUnload() {
    if (this.session) { try { this.session.abort(); } catch (e) {} }
  },

  loadCapacity() {
    fetch(this.data.apiBase + '/api/capacity')
      .then((r) => r.json())
      .then((d) => this.setData({ capacity: d }))
      .catch(() => this.setData({ err: '连不上后端' }));
  },

  onKeyDown(event) {
    if (event.code === 'Enter' && !this.session) this.startListen();
  },

  tapStart() { if (!this.session) this.startListen(); },

  startListen() {
    this.setData({ heard: '', report: null, err: '' });
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
      this.setData({ heard: text });
      this.report(text);
    };
    rec.onerror = (event) => this.setData({ err: '识别失败：' + (event.error || '') });
    rec.onend = () => { this.session = null; };
    try { rec.start(); } catch (e) { this.setData({ err: '无法启动麦克风' }); }
  },

  async report(text) {
    try {
      const r = await fetch(this.data.apiBase + '/api/report', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ text }),
      });
      if (!r.ok) throw new Error('HTTP ' + r.status);
      const d = await r.json();
      this.setData({ report: d });
      this.loadCapacity();
    } catch (e) {
      this.setData({ err: '回传失败，稍后重试' });
    }
  },

  makeQuote() {
    fetch(this.data.apiBase + '/api/quote', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ cost: 100, qty: 2000, urgency: 'normal' }),
    })
      .then((r) => r.json())
      .then((d) => this.setData({ quote: d }))
      .catch(() => this.setData({ err: '报价失败' }));
  },
};
</script>

<page>
  <view class="page">
    <text class="title">产能现场</text>

    <block wx:if="{{capacity}}">
      <view class="cap">
        <text class="line" wx:for="{{capacity.lines}}" wx:key="name">
          {{item.name}}｜余量 {{item.free}}%｜最早开工 {{item.earliest}}
        </text>
      </view>
    </block>
    <text wx:if="{{err}}" class="err">{{err}}</text>

    <text class="heard" wx:if="{{heard}}">{{heard}}</text>

    <block wx:if="{{report}}">
      <text class="ok">已回传：{{report.line}} · {{report.output}}件{{report.issue ? ' · 异常:' + report.issue : ''}}</text>
    </block>

    <block wx:if="{{quote}}">
      <view class="quote">
        <text class="row">理想 {{quote.ideal}}｜可成交 {{quote.deal}}</text>
        <text class="row">底价 {{quote.floor}}｜交期 {{quote.leadDays}}天</text>
      </view>
    </block>

    <text class="go" bindtap="tapStart">▶ 口述产量/异常</text>
    <text class="go2" bindtap="makeQuote">试算报价（示例参数）</text>
  </view>
</page>

<style>
.page {
  width: 100%; height: 100%;
  display: flex; flex-direction: column;
  padding: 12px 18px;
  background: #000; color: #0f0;
}
.title { font-size: 17px; font-weight: bold; margin-bottom: 6px; }
.cap { display: flex; flex-direction: column; margin-bottom: 6px; }
.line { font-size: 11px; line-height: 1.6; color: #af9; }
.heard { font-size: 12px; color: #7f7; margin: 4px 0; }
.ok { font-size: 12px; color: #0f0; margin: 4px 0; }
.quote { display: flex; flex-direction: column; margin: 4px 0; }
.row { font-size: 12px; line-height: 1.6; color: #ff0; }
.go {
  font-size: 13px; font-weight: bold;
  border: 1px solid #0f0; border-radius: 6px;
  padding: 5px 10px; align-self: flex-start; margin-top: 6px;
}
.go2 { font-size: 11px; color: #4a4; margin-top: 6px; }
.err { font-size: 11px; color: #f66; }
</style>
