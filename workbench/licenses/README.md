# 新增运行依赖

- node-pty 1.1.0：Microsoft 维护的伪终端库，MIT；许可见 node-pty-MIT.txt。依赖包随附的原生组件、winpty 和 node-addon-api 许可由 npm 包保留，不删减。
- @xterm/xterm 6.0.0：xterm.js，MIT；许可见 xterm-MIT.txt。
- @xterm/addon-fit 0.11.0：xterm.js 尺寸适配组件，MIT；许可见 xterm-addon-fit-MIT.txt。

版本和完整性校验由 package-lock.json 固定。通过 npm ci 获取原始分发包，不将本机 node_modules 打进源码包。
