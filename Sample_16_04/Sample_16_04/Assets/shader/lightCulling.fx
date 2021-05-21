/*!
 * @brief �|�C���g���C�g�̉e���͈͂��^�C���x�[�X�Ōv�Z����R���s���[�g�V�F�[�_�[
 */

// ��x�Ɏ��s�����X���b�h���B
#define TILE_WIDTH 16
#define TILE_HEIGHT 16

// �^�C���̑����B
#define TILE_SIZE (TILE_WIDTH * TILE_HEIGHT)

// �f�B���N�V�������C�g�B
struct DirectionLight
{
    float3 color; //���C�g�̃J���[�B
    float3 direction; //���C�g�̕����B
};

// �|�C���g���C�g�B
struct PointLight
{
    float3 position;        //���W�B
    float3 positionInView;  //�J������Ԃł̍��W�B
    float3 color;           //�J���[�B
    float range;            //�͈́B
};

static const int NUM_DIRECTION_LIGHT = 4;   //�f�B���N�V�������C�g�̐��B
static const int MAX_POINT_LIGHT = 1000;    //�|�C���g���C�g�̍ő吔�B

// �萔�o�b�t�@�[
cbuffer cbCameraParam : register(b0)
{
    float4x4 mtxProj : packoffset(c0);      // ���e�s��
    float4x4 mtxProjInv : packoffset(c4);   // ���e�s��̋t�s��
    float4x4 mtxViewRot : packoffset(c8);
};

cbuffer Light : register(b1)
{
    DirectionLight directionLight[NUM_DIRECTION_LIGHT];
    PointLight pointLight[MAX_POINT_LIGHT];
    float4x4 mViewProjInv;  //�r���[�v���W�F�N�V�����s��̋t�s��B
    float4 screenParam;     // �X�N���[���p�����[�^�inear, far, screenWidth, screenHeight�j
    float3 eyePos;          //���_�B
    float specPow;          //�X�y�L�����̍i��B
    int numPointLight;      //�|�C���g���C�g�̐��B
};

// ����
// �[�x�e�N�X�`���B
Texture2D depthTexture : register(t0);

// �o�͗p�̃o�b�t�@�B
RWStructuredBuffer<uint> rwLightIndices : register( u0 ); // ���C�g�C���f�b�N�X�o�b�t�@�[
RWStructuredBuffer<float> hoge : register(u1); // ���C�g�C���f�b�N�X�o�b�t�@�[

// ���L�������B
groupshared uint sMinZ; //�^�C���̍ŏ��[�x�B
groupshared uint sMaxZ; //�^�C���̍ő�[�x�B
groupshared uint sTileLightIndices[MAX_POINT_LIGHT]; //�^�C���ɐڐG���Ă���|�C���g���C�g�̃C���f�b�N�X�B
groupshared uint sTileNumLights; //�^�C���ɐڐG���Ă���|�C���g���C�g�̐��B

groupshared uint ligNum = 0;

/*!
 * @brief �^�C�����Ƃ̎����䕽�ʂ����߂�B
 */
void GetTileFrustumPlane( out float4 frustumPlanes[6], uint3 groupId )
{
    // �^�C���̍ő�E�ŏ��[�x�𕂓������_�ɕϊ�
    float minTileZ = asfloat(sMinZ);
    float maxTileZ = asfloat(sMaxZ);

    // Intel�̃T���v���Ɣ����ɈႤ�͉̂E��n�ł���Ă��邩��
    // ���ƁAIntel�̃T���v���͔����ɊԈ���Ă�Ǝv��
    float2 tileScale = screenParam.zw * rcp( float(2 * TILE_WIDTH) );
    float2 tileBias = tileScale - float2(groupId.xy);

    float4 c1 = float4(mtxProj._11 * tileScale.x, 0.0, tileBias.x, 0.0);
    float4 c2 = float4(0.0, -mtxProj._22 * tileScale.y, tileBias.y, 0.0);
    float4 c4 = float4(0.0, 0.0, 1.0, 0.0);

    frustumPlanes[0] = c4 - c1; // Right
    frustumPlanes[1] = c4 + c1; // Left
    frustumPlanes[2] = c4 - c2; // Top
    frustumPlanes[3] = c4 + c2; // Bottom
    frustumPlanes[4] = float4(0.0, 0.0, 1.0, -minTileZ);
    frustumPlanes[5] = float4(0.0, 0.0, -1.0, maxTileZ);

    // �@�������K������Ă��Ȃ�4�ʂɂ��Ă������K������
    [unroll]
    for (uint i = 0; i < 4; ++i)
    {
        frustumPlanes[i] *= rcp( length( frustumPlanes[i].xyz ) );
    }
}

/*!
 * @brief �J������Ԃł̍��W���v�Z����B
 */
float3 ComputePositionInCamera( uint2 globalCoords )
{
    float2 st = ((float2)globalCoords + 0.5) * rcp( screenParam.zw );
    st = st * float2( 2.0, -2.0 ) - float2( 1.0, -1.0 );
    float3 screenPos;
    screenPos.xy = st.xy;
    screenPos.z = depthTexture.Load(uint3(globalCoords, 0.0f));
    float4 cameraPos = mul(mtxProjInv, float4(screenPos, 1.0f));

    return cameraPos.xyz / cameraPos.w;
}

/*!
 * @brief CSMain
 */
[numthreads(TILE_WIDTH, TILE_HEIGHT, 1)]
void CSMain(
    uint3 groupId          : SV_GroupID,
    uint3 dispatchThreadId : SV_DispatchThreadID,
    uint3 groupThreadId    : SV_GroupThreadID
)
{
    // �^�C�����ł̃C���f�b�N�X�����߂�
    uint groupIndex = groupThreadId.y * TILE_WIDTH + groupThreadId.x;
    // ���C�g�̐����擾����
    //���L������������������B
    if(groupIndex == 0)
    {
        sTileNumLights = 0;
        sMinZ = 0x7F7FFFFF; // float�̍ő�l
        sMaxZ = 0;
    }

    uint2 frameUV = dispatchThreadId.xy;

    //�r���[��Ԃł̍��W���v�Z����B
    float3 posInView = ComputePositionInCamera(frameUV);

    // �����œ��������
    GroupMemoryBarrierWithGroupSync();

    // �^�C���̍ő�E�ŏ��[�x�����߂�
    // ���̏����͕��񂷂�X���b�h�S�ĂŔr���I�ɏ��������
    InterlockedMin( sMinZ, asuint(posInView.z) );
    InterlockedMax( sMaxZ, asuint(posInView.z) );

    // �����œ�������邱�ƂŃ^�C���̍ő�E�ŏ��[�x�𐳂������̂ɂ���
    GroupMemoryBarrierWithGroupSync();

    // �^�C���̐�������߂�
    float4 frustumPlanes[6];
    GetTileFrustumPlane( frustumPlanes, groupId );

    // �^�C���ƃ|�C���g���C�g�̏Փ˔���
    for (uint lightIndex = groupIndex; lightIndex < numPointLight; lightIndex += TILE_SIZE)
    {
        PointLight light = pointLight[lightIndex];

        // �^�C���Ƃ̔���
        bool inFrustum = true;
        for (uint i = 0; i < 6; ++i)
        {
            float4 lp = float4(light.positionInView, 1.0f);
            float d = dot( frustumPlanes[i], lp );
            inFrustum = inFrustum && (d >= -light.range);
        }

        // �^�C���ƏՓ˂��Ă���ꍇ
        if (inFrustum)
        {
            uint listIndex;
            InterlockedAdd( sTileNumLights, 1, listIndex );
            sTileLightIndices[listIndex] = lightIndex;
        }
    }

    // �����œ��������ƁAsTileLightIndices�Ƀ^�C���ƏՓ˂��Ă��郉�C�g�̃C���f�b�N�X���ς܂�Ă���
    GroupMemoryBarrierWithGroupSync();

    // ���C�g�C���f�b�N�X���o�̓o�b�t�@�ɏo��
    uint numCellX = (screenParam.z + TILE_WIDTH - 1) / TILE_WIDTH;
    uint tileIndex = floor( frameUV.x / TILE_WIDTH ) + floor( frameUV.y / TILE_WIDTH ) * numCellX;
    uint lightStart = numPointLight * tileIndex;
    for (uint lightIndex = groupIndex; lightIndex < sTileNumLights; lightIndex += TILE_SIZE)
    {
        rwLightIndices[lightStart + lightIndex] = sTileLightIndices[lightIndex];
    }
   
    if ((groupIndex == 0) && (sTileNumLights < numPointLight))
    {
        //-1�Ŕԕ��B
        rwLightIndices[lightStart + sTileNumLights] = 0xffffffff;
    }
}