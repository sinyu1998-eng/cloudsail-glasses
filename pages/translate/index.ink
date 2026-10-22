<script def>
{
  "navigationBarTitleText": "实时翻译"
}
</script>

<script setup>
// 中↔英实时翻译：语音说中文 → 端侧大模型翻译 → 屏幕显示 + 朗读英文
// 翻译文本由 LanguageModel 处理（非数字类任务，允许大模型）
import { LanguageModel } from 'language-model';

export default {
  data: {
    apiBase: 'http://192.168.1.100:8000',
    state: 'idle',
    src: '',
    dst: '',
    errMsg: '',
    langs: [
      { code: 'en', label: '英语' },
      { code: 'ru', label: '俄语' },
      { code: 'es', label: '西班牙语' },
    ],
    langIdx: 0,
  },
  llm: null,
  session: null,

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
          content: 'You are a business translator. Translate the user Chinese sentence into the requested target language. Output ONLY the translation, nothing else.'
        }],
      });
    } catch (e) { this.llm = null; }
  },

  onKeyDown(event) {
    if (event.code === 'Enter' && (this.data.state === 'idle' || this.data.state === 'done')) this.startListen();
  },
  tapStart() { this.startListen(); },

  startListen() {
    if (this.session) { try { this.session.abort(); } catch (e) {} }
    this.setData({ state: 'listening', src: '', dst: '', errMsg: '' });
    const rec = new SpeechRecognition();
    this.session = rec;
    rec.lang = 'zh-CN';
    rec.onresult = (event) => {
      const res = event.results;
      if (!res || !res.length) return;
      const last = res[res.length - 1];
      const text = (last && last[0] && last[0].transcript) || '';
      if (!text) return;
      this.setData({ src: text, state: 'translating' });
      this.translate(text);
    };
    rec.onerror = (event) => this.setData({ state: 'error', errMsg: '识别失败：' + (event.error || '') });
    rec.onend = () => { this.session = null; };
    try { rec.start(); } catch (e) { this.setData({ state: 'error', errMsg: '无法启动麦克风' }); }
  },

  tapLang() {
    const i = (this.data.langIdx + 1) % this.data.langs.length;
    this.setData({ langIdx: i, dst: '', state: 'idle' });
  },

  async translate(text) {
    const target = this.data.langs[this.data.langIdx].label;
    let out = '';
    if (this.llm) {
      try { out = (await this.llm.prompt(text) || '').trim(); } catch (e) { out = ''; }
    }
    if (!out) {
      try {
        const r = await fetch(this.data.apiBase + '/api/translate', {
          method: 'POST', headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ text, target }),
        });
        if (r.ok) { const d = await r.json(); out = d.text || ''; }
      } catch (e) {}
    }
    if (!out) { this.setData({ state: 'error', errMsg: '翻译不可用（端侧模型与后端都不通）' }); return; }
    this.setData({ dst: out, state: 'done' });
    try { speechSynthesis.speak(new SpeechSynthesisUtterance(out), 'enqueue'); } catch (e) {}
  },

  stateText(s) {
    return { idle: '按确认键开始说中文', listening: '请说…', translating: '翻译中…',
             done: '已朗读英文', error: '出错了' }[s] || '';
  },
};
</script>

<page>
  <view class="page">
    <text class="state">{{stateText(state)}}</text>
    <text class="src" wx:if="{{src}}">{{src}}</text>
    <text class="dst" wx:if="{{dst}}">{{dst}}</text>
    <text class="err" wx:if="{{errMsg}}">{{errMsg}}</text>
    <text class="lang" bindtap="tapLang">目标语言：{{langs[langIdx].label}}（点按切换）</text>
    <text class="go" bindtap="tapStart">▶ 重新说</text>
  </view>
</page>

<style>
.page { width: 100%; height: 100%; display: flex; flex-direction: column;
        padding: 14px 18px; background: #000; color: #0f0; }
.state { font-size: 13px; font-weight: bold; margin-bottom: 8px; }
.src { font-size: 13px; color: #7f7; line-height: 1.4; margin-bottom: 6px; }
.dst { font-size: 15px; color: #ff0; line-height: 1.45; margin-bottom: 6px; }
.err { font-size: 11px; color: #f66; }
.lang { font-size: 12px; color: #ff0; margin: 4px 0; }
.go { font-size: 13px; border: 1px solid #0f0; border-radius: 6px;
      padding: 5px 10px; align-self: flex-start; margin-top: 6px; }
</style>
