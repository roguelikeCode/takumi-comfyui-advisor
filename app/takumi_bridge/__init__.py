# [Why] ComfyUIにカスタムノード/拡張機能として認識させるため
# [What] serverモジュールをインポートし、Webディレクトリをマッピングする

from .server import *

# WEB_DIRECTORY は、ComfyUIが静的ファイル(JS/CSS)を探す場所を指定する
# ここで指定したフォルダ内のファイルは、ブラウザからアクセス可能になる
WEB_DIRECTORY = "./js"

# ノードクラスは今回は登録しない（サーバー拡張のみ）が、形式上必要
NODE_CLASS_MAPPINGS = {}
NODE_DISPLAY_NAME_MAPPINGS = {}

print(">>> [TakumiBridge] Loaded. Web extension ready.")