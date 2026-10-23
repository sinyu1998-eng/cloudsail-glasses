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
    apiBase: 'http://192.168.0.49:8000',
    state: 'idle',
    src: '',
    dst: '',
    errMsg: '',
    langs: [
      { code: 'auto', label: '自动识别' },
      { code: '英语', label: '英语' },
      { code: '俄语', label: '俄语' },
      { code: '西班', label: '西班牙语' },
      { code: '葡萄', label: '葡萄牙语' },
      { code: '法语', label: '法语' },
      { code: '德语', label: '德语' },
      { code: '意大', label: '意大利语' },
      { code: '阿拉', label: '阿拉伯语' },
      { code: '日语', label: '日语' },
      { code: '韩语', label: '韩语' },
      { code: '土耳', label: '土耳其语' },
      { code: '越南', label: '越南语' },
      { code: '泰语', label: '泰语' },
      { code: '印尼', label: '印尼语' },
      { code: '印地', label: '印地语' },
    ],
    langIdx: 0,
    detected: '',
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
          content: 'You are a business translator. The user message starts with a tag like [英语] or [AUTO], followed by a sentence. Translate the sentence into the language named in the tag. If the tag is [AUTO]: translate Chinese into English, and any other language into Chinese. Output ONLY the translation, nothing else.'
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
    rec.interimResults = true;  // 边说边显示，降低感知延迟
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
    const lang = this.data.langs[this.data.langIdx];
    const auto = lang.code === 'auto';
    const target = auto ? 'auto' : lang.label;
    let out = '';
    if (this.llm) {
      try { out = ((await this.llm.prompt((auto ? '[AUTO] ' : '[' + lang.label + '] ') + text)) || '').trim(); } catch (e) { out = ''; }
    }
    if (!out) {
      try {
        const r = await fetch(this.data.apiBase + '/api/translate', {
          method: 'POST', headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ text, target }),
        });
        if (r.ok) { const d = await r.json(); out = d.text || ''; if (auto && d.detected) this.setData({ detected: d.detected }); }
      } catch (e) {}
    }
    if (!out) { this.setData({ state: 'error', errMsg: '翻译不可用（端侧模型与后端都不通）' }); return; }
    this.setData({ dst: out, state: 'done' });
    try { speechSynthesis.speak(new SpeechSynthesisUtterance(out), 'enqueue'); } catch (e) {}
  },

  stateText(s) {
    return { idle: '按确认键，说什么语言都行', listening: '请说…', translating: '翻译中…',
             done: '已朗读译文', error: '出错了' }[s] || '';
  },
};
</script>

<page>
  <view class="page">
    <text class="state">{{stateText(state)}}</text>
    <text class="src" wx:if="{{src}}">{{src}}</text>
    <text class="dst" wx:if="{{dst}}">{{dst}}</text>
    <text class="err" wx:if="{{errMsg}}">{{errMsg}}</text>
    <text class="lang" bindtap="tapLang">{{langs[langIdx].label === '自动识别' ? '目标语言：自动（点按切换）' : '目标语言：' + langs[langIdx].label + '（点按切回自动）'}}</text>
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
