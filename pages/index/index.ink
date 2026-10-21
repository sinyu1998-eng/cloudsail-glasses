<script def>
{
  "navigationBarTitleText": "云帆现场助手"
}
</script>

<script setup>
export default {
  data: {
    tip: '按镜腿键或说指令进入',
    items: [
      { key: 'visit', label: '客户拜访' },
      { key: 'capacity', label: '产能/报价' },
    ],
    focus: 0,
  },

  onKeyDown(event) {
    if (event.code === 'ArrowDown') {
      this.setData({ focus: (this.data.focus + 1) % this.data.items.length });
    } else if (event.code === 'ArrowUp') {
      this.setData({ focus: (this.data.focus + this.data.items.length - 1) % this.data.items.length });
    }
  },

  onKeyUp(event) {
    if (event.code === 'Enter') {
      const item = this.data.items[this.data.focus];
      if (item.key === 'visit') {
        window.open('pages/visit/index', '_self');
      } else {
        window.open('pages/capacity/index', '_self');
      }
    }
  },

  onVoiceWakeup(event) {
    const t = (event.keyword || '') + '';
    if (t.indexOf('拜访') >= 0 || t.indexOf('客户') >= 0) {
      window.open('pages/visit/index', '_self');
    } else if (t.indexOf('产能') >= 0 || t.indexOf('报价') >= 0) {
      window.open('pages/capacity/index', '_self');
    }
  },

  tapItem(event) {
    const key = event.target.dataset.key;
    if (key === 'visit') window.open('pages/visit/index', '_self');
    if (key === 'capacity') window.open('pages/capacity/index', '_self');
  },
};
</script>

<page>
  <view class="page">
    <text class="title">云帆现场助手</text>
    <view class="menu">
      <view
        wx:for="{{items}}"
        wx:key="key"
        class="item {{focus === index ? 'on' : ''}}"
        data-key="{{item.key}}"
        bindtap="tapItem"
      >
        <text>{{item.label}}</text>
      </view>
    </view>
    <text class="tip">{{tip}}</text>
  </view>
</page>

<style>
.page {
  width: 100%;
  height: 100%;
  display: flex;
  flex-direction: column;
  justify-content: center;
  padding: 16px 20px;
  background: #000;
  color: #0f0;
}
.title {
  font-size: 20px;
  font-weight: bold;
  margin-bottom: 12px;
}
.menu { display: flex; flex-direction: column; }
.item {
  padding: 8px 12px;
  border: 1px solid #0f0;
  border-radius: 6px;
  margin-bottom: 8px;
  font-size: 15px;
}
.item.on { background: #0f0; color: #000; }
.tip { font-size: 11px; color: #4a4; margin-top: 4px; }
</style>
