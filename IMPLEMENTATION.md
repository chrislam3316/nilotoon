# Unity 6 / URP 17 character shader extension

這是根據功能描述獨立實作的版本，保留原本 MIT 授權及 shader 名稱。
不是 NiloToon 商業版原始碼，也不宣稱效果、效能或資產格式與其相同。
原 README 保留作上游介紹；本分支的實際功能及安裝方法以本文件為準。

## 最快試透視修正

1. 將根目錄所有 `.shader`、`.hlsl` 以及 `Runtime/`、`Editor/` 複製到 Unity 專案的同一個 `Assets/NiloToon/` 目錄。保留子目錄結構。
2. 使用 **Unity 6.0 / URP 17、Universal Renderer、Render Graph 開啟**。這份程式不提供 Compatibility Mode 的 Renderer Feature 實作。
3. 材質選 `SimpleURPToonLitExample(With Outline)`，指定 Base Map。新功能預設關閉。
4. 在角色根節點加入 `NiloToonCharacter`。將 `pivot` 指向角色胸口附近、身體／臉／頭髮共用的 Transform；`head` 的 +Z 是臉正前方，+X 是右方。
5. 將 `perspectiveCorrection` 調到 0.5–0.8。0 是原本透視；1 是以角色 pivot 距離決定大小的弱透視投影。
6. 兩個攝影機放在不同角度，可以同時輸出 Game View／RenderTexture。**不需要指定主鏡頭，也沒有使用 `Camera.main`。**
7. `Tools > Nilo Toon > Create Two Camera Demo` 會建立新資產資料夾及額外示範場景，包含同一角色和兩個方向不同的鏡頭；不覆寫原場景。選角色調整 correction，觀察近處的鼻和手。

單獨使用透視修正、一般描邊、光照、貼圖、淡出或溶解，不必加入 Renderer Feature。
Controller 會覆蓋所選材質槽的角色 tint、fade、dissolve、outline/rim multiplier、pivot 和 correction；掛上後以 Controller 為準。
換材質、增減子物件後執行 Controller 的 `Refresh Targets`。

## 為甚麼不同鏡頭都能看

網格資產、骨架和 Transform 沒有被壓扁。每次 draw 都使用 **目前正在繪製的攝影機** 的 View／Projection 矩陣。

對某個頂點，設 `d` 是這個鏡頭看到的頂點深度，`c` 是同一鏡頭看到的角色 pivot 深度，`a` 是修正強度：

```text
effectiveDepth = lerp(d, c, a)
screenXY       = project(vertexViewXY, effectiveDepth).xy / virtualClipW
```

當 a=1，同一角色所有頂點都用 c 作投影除數，近處鼻子／手不會因為更靠近鏡頭而額外放大。
角色走遠時 c 仍增加，所以整個角色仍會隨距離變小；這不是把全場景切成正交相機。
鏡頭 A 和 B 的 d、c、viewXY 分別計算：A 不會把 B 要看的網格永久壓平。

實作在 `NiloPerspectiveCorrection.hlsl`。重新透過完整 Projection 矩陣投影，保留 lens shift／非對稱投影。
最後使用 virtual clip.w 做貼圖及世界座標的插值，並將 clip.z 改成 `originalNdcDepth * virtualClipW`，保留每個**頂點**的原始深度。
這避免完全修正時仍用舊 w 插值，造成貼圖被透視拉扯。

同一函數套用到 Forward、一般／額外 Outline、DepthOnly、DepthNormals、HairDepth、EyeOverlay 和 CharacterMask。
ShadowCaster 刻意使用原本 3D 網格，因為光源陰影應該在多鏡頭之間一致。
正交相機直接略過；pivot 太靠近 near plane 時淡出修正，頂點或 pivot 在近裁切面後方時不套用。

**它仍然是視角相關的美術投影，不是物理上存在的平面角色。**

- 保留頂點深度不代表修改後每個像素都等於原相機射線上的真實世界位置。SSAO、SSR、接觸陰影、景深、與牆壁交界可能不完全相符。
- 真實投影陰影、碰撞和光源距離使用原始 3D 位置。強修正時，視覺輪廓與陰影／碰撞位置可能分離。
- CPU 的 frustum／occlusion culling 不知道 shader 的投影改變。Controller 會增加 `localBounds`，但固定 padding 不能保證所有 FOV、近距離及極端角度；需要測試並增加 `boundsPadding`。必要時關閉角色 occlusion culling。
- 不提供 MotionVectors pass；TAA／運動模糊的物件運動向量不完整。驗證時先用 FXAA／SMAA／MSAA。
- 已有 stereo 矩陣及 eye-index 路徑，但 XR、反射相機、相機 stack、動態解析度和非 D3D11 平台尚未實機驗證。不要把多個一般相機通過的數學檢查視為 XR 支援認證。

## Renderer Feature 設定

在每個相關攝影機所用的 Universal Renderer Data 加入 `NiloToonRendererFeature`：

- `Character Layers` 包含角色所用 layer。
- `Post Process Shader` 指定根目錄 `NiloToonPostProcess.shader`，確保 Player build 保留它。
- Feature 會要求 current-camera Depth Texture；頭髮 depth／ID texture 每個鏡頭獨立產生，鏡頭開始時重設有效旗標，避免沿用上個鏡頭的資料。
- 此 feature 針對 Game／SceneView 攝影機。材質中的純投影修正仍由各次 draw 的矩陣決定。
- 頭髮材質開 `Hair depth caster`；臉材質開 `Face`，增加 `Hair shadow strength`。同一角色必須有 Controller，讓頭髮／臉取得相同非零 Character ID。
- 眼睛／眉毛材質開 `Eye or eyebrow overlay`，增加 `Eye overlay opacity`。覆蓋只在本角色頭髮位於眼前且場景 depth 對應那層頭髮時發生，不是無條件 ZTest Always 畫穿所有物體。
- Rim／頭髮陰影寬度以目前渲染解析度的 pixel 為單位；Render Scale 改變會影響最終顯示寬度。
- 在 Volume Profile 加 `Nilo Toon > Character Style`，勾 `Enable` 和需要的 override。角色 tint／shadow／rim 在 opaque 之前設定；後製另需 Camera 的 Post Processing 開啟。
- 自訂 glow 會加到顏色，再交給 URP 後製。若同時開 URP Bloom，兩者可能重複增加光暈；以實際風格調整。

## 功能對照與需要的資料

| 類別 | 這次實作 | 條件／限制 |
|---|---|---|
| 角色透視 | 每個 draw 使用當前相機矩陣；共享角色 pivot | 上述深度／culling 取捨 |
| 臉部光照 | 頭部方向驅動 SDF 明暗、左右 UV 鏡像 | 要作者提供 FaceShadowMap，R 為 0–1 光照角度門檻；不是自動從普通貼圖推導 SDF |
| 平滑描邊 | 像素寬度外擴、UV4 法線烘焙、深度 mask | 在 `Tools > Nilo Toon > Bake Smooth Outline Normals` 產生新 mesh asset，再開 `Use baked UV4 smooth normals` |
| 法線烘焙 | 相同頂點位置平均法線，轉入切線空間以跟隨蒙皮 | 保留原本光照法線／原 FBX；需可讀 mesh、有效 normals/tangents；UV4 被新資產使用；近似接縫／不同骨權重需美術處理 |
| 頭髮陰影 | 每個相機的 hair depth＋角色 ID，依主光方向位移取樣 | 是 2D 近似；只記錄最近一層頭髮，重疊角色可能缺少被擋住的頭髮資訊；不會模擬離屏頭髮 |
| 固定寬 Rim | 深度鄰域取樣，沿視空間法線方向使用 pixel offset | 需要 Feature／深度 prepass；細部法線／遮擋／畫面邊界可能不連續 |
| 眼眉在頭髮前 | 自身頭髮 ID、深度遮擋檢查後重畫 | 使用眼眉材質形狀／alpha clipping；不是任意透明髮絲排序系統 |
| 高光／材質 | URP GGX、metallic／roughness／specular mask；MatCap 加算、乘算、替換 | Toon 與 GGX 混合，不含完整 reflection probe PBR；SSS 為無厚度背光近似 |
| 額外貼圖 | Normal、detail color、單步 parallax、AO、emission、shadow tint | MaterialMask 的 R=metallic、G=roughness、B=specular；roughness 為粗糙度不是 smoothness |
| 顏色控制 | 材質／角色 tint、shadow tint map、最終／描邊 HSV | Hue 為 0–1 周期，S/V 是倍率；採用 BaseMap 的 sampler 設定共用大多數材質貼圖 |
| 角色特效 | Dither visibility、dissolve 發光邊、rim／outline 倍率、額外描邊 | 所有幾何 pass 共用 clip 邏輯；沒有半透明 alpha blend 主材質 |
| 全域控制 | Volume 角色色彩、飽和度、rim、接收陰影強度／顏色 | 不調整 URP light shadow atlas／cascade 設定 |
| 分區 Bloom | 可見角色 mask、角色／背景獨立強度、四分之一解析度分離模糊 | 單一尺度 glow；沒有商業多層 bloom pyramid；透明前景未分類，需場景測試 |
| 動漫後製 | 飽和度、對比、色階量化，保留 HDR >1 部分 | 顏色效果，不是通用後製套件 |
| Shader variants | 減少原範例未使用的 keywords，alpha clipping 使用 local shader_feature，URP 自動 stripping | 未新增會誤刪 runtime variant 的專用 stripper；多數開關是 uniform，關閉不代表程式碼完全不在 GPU program |

未實作 README 展示區的 Phong tessellation、任意自動臉部資產生成、商業版全部 MatCap 混合模式或所有未公開功能。

## 資產與效能注意

- 主 shader 名稱不變，現有材質可繼續找到它。描邊寬度改為 pixel；四個舊版無作用的光照滑桿現已生效，舊材質保存的數值會開始影響畫面。
- Controller 明確擁有所選 material-index 的 MaterialPropertyBlock。啟用前的 override 會保留，停用時還原原 snapshot；其他腳本不要同時擁有同一槽。MPB 會犧牲這些 draw 的 SRP Batcher 路徑。
- Normal map 用 Unity Normal Map import；Face SDF、mask、height、dissolve 是資料貼圖，關閉 sRGB。Base／detail／MatCap／shadow tint 是顏色貼圖。
- UV4 法線方向會跟隨骨架的 TBN，但沒有獨立的 blendshape smooth-normal delta。
- Feature 增加 depth prepass、hair、overlay／outline，以及可選的 mask/glow draw；尚無目標裝置效能量測。
- 目前目標為 Shader Model 4.5；未提供 WebGL／低階行動裝置降級分支。

## 驗證

```powershell
python -B -m unittest discover -s Tests -p '*_test.py'
python -B Tests/compile_hlsl.py
```

`compile_hlsl.py` 只使用標準函式庫及 Windows `d3dcompiler_47.dll`，缺少的 Unity 官方 6000.0/staging 標頭會快取到忽略的 `.validation/`。
使用 Unity 的 unified half precision 設定；獨立 FXC 忽略不相關的空 `PopMarker` instrumentation macro。
這是實際 D3D11 HLSL 入口編譯，**不是 Unity ShaderLab／C#／Render Graph 的整合編譯**。

匯入 Unity 後執行 `Tools > Nilo Toon > Run Self Checks`，檢查 shader 匯入錯誤、pass 存在、平滑法線重建、Controller 參數一致及停用還原。
接著在示範場景測試兩個相機、改 FOV、Scene View、RenderTexture、near plane、角色走到畫面邊緣、互相重疊角色、眼前加牆、開關 depth normals／SSAO／MSAA。
`Run Self Checks` 本身不會替代 GPU 畫面測試，也不保證每個尚未使用的 Unity variant 已被編譯。

參考：
- [Unity 6 built-in shader variables](https://docs.unity3d.com/6000.0/Documentation/Manual/SL-UnityShaderVariables.html)
- [Unity 6 Render Graph material blits](https://raw.githubusercontent.com/Unity-Technologies/Graphics/6000.0/staging/Packages/com.unity.render-pipelines.core/Runtime/RenderGraph/RenderGraphUtilsBlit.cs)
- [Unity 6 BRDF](https://raw.githubusercontent.com/Unity-Technologies/Graphics/6000.0/staging/Packages/com.unity.render-pipelines.universal/ShaderLibrary/BRDF.hlsl)
