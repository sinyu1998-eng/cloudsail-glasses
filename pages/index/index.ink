<script def>
{
  "navigationBarTitleText": "云帆现场助手"
}
</script>

<script setup>
// 极简版：全软件只有一个动作——说话。
// 说拜访/客户 → 自动进 CRM + 当场出三档报价；说产量/异常 → 自动上报产能。
import { LanguageModel } from 'language-model';

export default {
  data: {
    apiBase: 'http://192.168.1.100:8000',   // TODO: 换成电脑局域网 IP
    state: 'idle',        // idle | listening | parsing | done | error
    heard: '',
    card: null,           // 拜访结构化 {company, person, product, qty, note}
    quote: null,          // 三档报价 {ideal, deal, floor, leadDays}
    report: null,         // 产能上报结果 {line, output, issue}
    errMsg: '',
    demoCost: 5.6,        // 演示单件成本（正式版从成本表读取，不由大模型生成）
  },

  session: null,
  llm: null,

  onReady() { this.initLLM(); },

  onUnload() {
    if (this.session) { try { this.session.abort(); } catch (e) {} }
    if (this.llm) this.llm.destroy();
  },

  async initLLM() {
    try {
      if ((await LanguageModel.availability()) !== 'available') { this.llm = null; return; }
      this.llm = await LanguageModel.create({
        initialPrompts: [{
          role: 'system',
          content: '你是信息抽取器。从用户口述中抽取客户拜访信息，只输出 JSON，不要输出任何其他文字。字段：company(公司名，未知填空字符串)、person(联系人)、product(产品/需求)、qty(数量，字符串)、note(其他要点)。'
        }],
      });
    } catch (e) { this.llm = null; }
  },

  onKeyDown(event) {
    if (event.code === 'Enter' && (this.data.state === 'idle' || this.data.state === 'done')) {
      this.startListen();
    }
  },

  onKeyUp(event) {
    if (event.code === 'Backspace' && (this.data.state === 'listening' || this.data.state === 'parsing')) {
      try { this.session && this.session.abort(); } catch (e) {}
      this.setData({ state: 'idle' });
      event.preventDefault();
    }
  },

  // 语音唤醒：说“翻译”去翻译页，其他任何指令都直接开始记录
  onVoiceWakeup(event) {
    const t = (event.keyword || '') + '';
    if (t.indexOf('翻译') >= 0) { window.open('pages/translate/index', '_self'); return; }
    if (this.data.state === 'idle' || this.data.state === 'done') this.startListen();
  },

  tapStart() { if (this.data.state === 'idle' || this.data.state === 'done') this.startListen(); },

  startListen() {
    if (this.session) { try { this.session.abort(); } catch (e) {} }
    this.setData({ state: 'listening', heard: '', card: null, quote: null, report: null, errMsg: '' });
    const rec = new SpeechRecognition();
    this.session = rec;
    rec.lang = 'zh-CN';
    rec.interimResults = true;
    rec.onresult = (event) => {
      const res = event.results;
      if (!res || !res.length) return;
      const last = res[res.length - 1];
      const text = (last && last[0] && last[0].transcript) || '';
      if (!text) return;
      const isFinal = last.isFinal !== false;
      this.setData({ heard: text });
      if (isFinal) { this.setData({ state: 'parsing' }); this.parse(text); }
    };
    rec.onerror = (event) => {
      this.setData({ state: 'error', errMsg: '识别失败：' + (event.error || '未知') });
    };
    rec.onend = () => { this.session = null; };
    try { rec.start(); } catch (e) {
      this.setData({ state: 'error', errMsg: '无法启动麦克风' });
    }
  },

  async parse(text) {
    // 产能上报：提到线体/产量/异常词就走 report
    if (/[一二三123]\s*号?线/.test(text) || /(不良|停机|故障|缺料|返工)/.test(text)) {
      this.doReport(text);
      return;
    }
    // 拜访：结构化 → 自动进 CRM → 同屏出报价
    let card = null;
    if (this.llm) {
      try { card = JSON.parse(this.extractJSON(await this.llm.prompt(text))); } catch (e) { card = null; }
    }
    if (!card) {
      try {
        const r = await fetch(this.data.apiBase + '/api/extract', {
          method: 'POST', headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ text }),
        });
        if (r.ok) card = await r.json();
      } catch (e) {}
    }
    if (!card) card = { company: '', person: '', product: text, qty: '', note: '' };

    this.setData({ card });
    // 进 CRM（失败不阻塞报价）
    try {
      await fetch(this.data.apiBase + '/api/visits', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(card),
      });
      this.setData({ inCrm: true });
    } catch (e) {
      this.saveLocal();
      this.setData({ inCrm: false });
    }
    // 三档报价：确定性计算，大模型不碰数字
    const qtyNum = parseInt((card.qty + '').replace(/[^0-9]/g, ''), 10)
      || parseInt((text.match(/(\d{3,})/) || [])[1] || '', 10) || 1000;
    try {
      const r = await fetch(this.data.apiBase + '/api/quote', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ cost: this.data.demoCost, qty: qtyNum, urgency: 'normal' }),
      });
      if (r.ok) this.setData({ quote: await r.json() });
    } catch (e) {}
    this.setData({ state: 'done' });
  },

  async doReport(text) {
    try {
      const r = await fetch(this.data.apiBase + '/api/report', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ text }),
      });
      this.setData({ report: r.ok ? await r.json() : null, state: 'done', inCrm: null });
    } catch (e) {
      this.setData({ state: 'error', errMsg: '网络失败，稍后再试' });
    }
  },

  saveLocal() {
    try {
      const box = JSON.parse(wx.getStorageSync('cs_pending') || '[]');
      box.push(this.data.card);
      wx.setStorageSync('cs_pending', box.slice(-20));
    } catch (e) {}
  },

  extractJSON(s) {
    const a = s.indexOf('{');
    const b = s.lastIndexOf('}');
    return a >= 0 && b > a ? s.slice(a, b + 1) : '{}';
  },

  stateText(s) {
    return {
      idle: '按确认键，说一句话', listening: '请说话…（返回键停止）',
      parsing: '整理中…', done: '完成 ✓ 再按一次继续', error: '出错了',
    }[s] || '';
  },
};
</script>

<page>
  <view class="page">
    <text class="state">{{stateText(state)}}</text>

    <block wx:if="{{state === 'listening' || state === 'parsing'}}">
      <text class="heard">{{heard || '…'}}</text>
    </block>

    <block wx:if="{{state === 'done'}}">
      <block wx:if="{{card}}">
        <text class="row">公司：{{card.company || '—'}}</text>
        <text class="row">联系人：{{card.person || '—'}}</text>
        <text class="row" wx:if="{{card.qty}}">数量：{{card.qty}}</text>
        <text class="ok">{{inCrm === false ? '已存本地，联网后补传' : '已入 CRM ✓'}}</text>
      </block>
      <block wx:if="{{quote}}">
        <view class="quote">
          <text class="p">理想 ¥{{quote.ideal}} ／ 成交 ¥{{quote.deal}} ／ 底价 ¥{{quote.floor}}</text>
          <text class="s">交期 {{quote.leadDays}} 天 · 演示成本 ¥{{demoCost}}/件 · 数字为公式计算，可审计</text>
        </view>
      </block>
      <block wx:if="{{report}}">
        <view class="quote">
          <text class="p">{{report.line}} 产量 {{report.output || '—'}}{{report.issue ? ' · 异常：' + report.issue : ''}}</text>
          <text class="s">已上报产能看板 ✓</text>
        </view>
      </block>
    </block>

    <block wx:if="{{state === 'error'}}">
      <text class="err">{{errMsg}}</text>
    </block>

    <block wx:if="{{state === 'idle' || state === 'done'}}">
      <text class="go" bindtap="tapStart">▶ 说话</text>
      <text class="tip">说“拜访华信贸易找王总保温杯两千件”出报价；说“3号线今天1200件”报产能；说“翻译”进翻译</text>
    </block>
  </view>
</page>

<style>
.page {
  width: 100%; height: 100%;
  display: flex; flex-direction: column;
  padding: 14px 18px;
  background: #000; color: #0f0;
}
.state { font-size: 14px; font-weight: bold; margin-bottom: 8px; }
.heard { font-size: 13px; color: #7f7; line-height: 1.4; }
.row { font-size: 12px; line-height: 1.6; color: #af9; }
.ok { font-size: 12px; color: #0f0; margin-top: 4px; }
.quote { margin-top: 8px; display: flex; flex-direction: column; }
.p { font-size: 14px; font-weight: bold; color: #0f0; }
.s { font-size: 10px; color: #4a4; margin-top: 3px; line-height: 1.4; }
.go {
  font-size: 15px; font-weight: bold;
  border: 1px solid #0f0; border-radius: 6px;
  padding: 7px 16px; align-self: flex-start; margin-top: 10px;
}
.tip { font-size: 10px; color: #4a4; margin-top: 8px; line-height: 1.5; }
.err { font-size: 12px; color: #f66; }
</style>
