<script def>
{
  "navigationBarTitleText": "客户拜访"
}
</script>

<script setup>
// 核心流程：按确认键开始说话 → 语音识别 → 大模型抽成结构化字段 → 确认 → 提交后端
import { LanguageModel } from 'language-model';

export default {
  data: {
    apiBase: 'http://192.168.1.100:8000',
    state: 'idle',          // idle | listening | parsing | confirm | sending | done | error
    heard: '',              // 原始识别文本
    card: null,             // 结构化结果 { company, person, product, qty, note }
    errMsg: '',
  },

  session: null,
  llm: null,

  onReady() {
    this.initLLM();
  },

  onUnload() {
    if (this.session) { try { this.session.abort(); } catch (e) {} }
    if (this.llm) this.llm.destroy();
  },

  async initLLM() {
    try {
      if ((await LanguageModel.availability()) !== 'available') {
        // 端侧模型不可用时不阻塞，结构化会退回后端完成
        this.llm = null;
        return;
      }
      this.llm = await LanguageModel.create({
        initialPrompts: [{
          role: 'system',
          content: '你是信息抽取器。从用户口述中抽取客户拜访信息，只输出 JSON，不要输出任何其他文字。字段：company(公司名，未知填空字符串)、person(联系人)、product(产品/需求)、qty(数量，字符串)、note(其他要点)。'
        }],
      });
    } catch (e) {
      this.llm = null;
    }
  },

  onKeyDown(event) {
    if (event.code === 'Enter' && this.data.state === 'idle') {
      this.startListen();
    }
  },

  tapStart() { if (this.data.state === 'idle') this.startListen(); },

  tapConfirm() {
    if (this.data.state !== 'confirm') return;
    this.setData({ state: 'sending' });
    fetch(this.data.apiBase + '/api/visits', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(this.data.card),
    }).then((r) => {
      this.setData({ state: r.ok ? 'done' : 'error', errMsg: r.ok ? '' : ('HTTP ' + r.status) });
    }).catch((e) => {
      this.setData({ state: 'error', errMsg: '网络失败，记录已存本地待补传' });
      this.saveLocal();
    });
  },

  saveLocal() {
    try {
      const box = JSON.parse(wx.getStorageSync('cs_pending') || '[]');
      box.push(this.data.card);
      wx.setStorageSync('cs_pending', box.slice(-20));
    } catch (e) {}
  },

  startListen() {
    if (this.session) { try { this.session.abort(); } catch (e) {} }
    this.setData({ state: 'listening', heard: '', card: null });
    const rec = new SpeechRecognition();
    this.session = rec;
    rec.lang = 'zh-CN';
    rec.interimResults = false;
    rec.onresult = (event) => {
      let text = '';
      const res = event.results;
      if (res && res.length) {
        const last = res[res.length - 1];
        text = (last && last[0] && last[0].transcript) || '';
      }
      if (!text) return;
      this.setData({ heard: text, state: 'parsing' });
      this.parse(text);
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
    let card = null;
    if (this.llm) {
      try {
        const raw = await this.llm.prompt(text);
        card = JSON.parse(this.extractJSON(raw));
      } catch (e) { card = null; }
    }
    if (!card) {
      // 兜底：交给后端抽取（后端也有 LLM 时走这里）
      try {
        const r = await fetch(this.data.apiBase + '/api/extract', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ text }),
        });
        if (r.ok) card = await r.json();
      } catch (e) {}
    }
    if (!card) card = { company: '', person: '', product: text, qty: '', note: '' };
    this.setData({ card, state: 'confirm' });
  },

  extractJSON(s) {
    const a = s.indexOf('{');
    const b = s.lastIndexOf('}');
    return a >= 0 && b > a ? s.slice(a, b + 1) : '{}';
  },

  onKeyUp(event) {
    if (event.code === 'Backspace' && (this.data.state === 'listening' || this.data.state === 'parsing')) {
      try { this.session && this.session.abort(); } catch (e) {}
      this.setData({ state: 'idle' });
      event.preventDefault();
    }
  },

  stateText(s) {
    return {
      idle: '按确认键开始记录', listening: '请说话…（返回键停止）',
      parsing: '整理中…', confirm: '确认提交？', sending: '提交中…',
      done: '已入 CRM ✓', error: '出错了',
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

    <block wx:if="{{state === 'confirm' && card}}">
      <view class="card">
        <text class="row">公司：{{card.company || '—'}}</text>
        <text class="row">联系人：{{card.person || '—'}}</text>
        <text class="row">需求：{{card.product || '—'}}</text>
        <text class="row" wx:if="{{card.qty}}">数量：{{card.qty}}</text>
        <text class="row" wx:if="{{card.note}}">备注：{{card.note}}</text>
      </view>
      <text class="go" bindtap="tapConfirm">▶ 确认提交</text>
    </block>

    <block wx:if="{{state === 'error'}}">
      <text class="err">{{errMsg}}</text>
    </block>

    <block wx:if="{{state === 'idle' || state === 'done'}}">
      <text class="go" bindtap="tapStart">▶ 开始记录</text>
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
.card { display: flex; flex-direction: column; margin-bottom: 8px; }
.row { font-size: 12px; line-height: 1.6; color: #af9; }
.go {
  font-size: 14px; font-weight: bold;
  border: 1px solid #0f0; border-radius: 6px;
  padding: 6px 12px; align-self: flex-start;
}
.err { font-size: 12px; color: #f66; }
</style>
