// 頂点シェーダーへの入力頂点構造体
struct VSInput
{
    float4 pos : POSITION;
    float3 color : COLOR; // 頂点からカラーのデータを引っ張ってくる
};

// 頂点シェーダーの出力
struct VSOutput
{
    float4 pos : SV_POSITION;
    float3 color : COLOR; // カラーの情報も出力する
};

// 頂点シェーダー
VSOutput VSMain(VSInput In)
{
    VSOutput vsOut = (VSOutput)0;
    vsOut.pos = In.pos;
    vsOut.color = In.color; // カラーの情報を出力する
    return vsOut;
}

// ピクセルシェーダー
float4 PSMain(VSOutput vsOut) : SV_Target0
{
    return float4(1.0f, 1.0f , 0.0f, 1.0f);

}