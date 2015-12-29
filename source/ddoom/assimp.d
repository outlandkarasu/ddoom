/**
 *  ASSIMP関連のユーティリティモジュール
 */ 
module ddoom.assimp;

import std.algorithm : map;
import std.array : array, Appender;
import std.stdio : writefln;
import std.string : fromStringz, toStringz;
import std.format : format;

import derelict.assimp3.assimp;
import gl3n.linalg;

import ddoom.asset;

/// ASSIMP関連例外
class AssetException : Exception {
    @nogc @safe pure nothrow this(string msg, string file = __FILE__, size_t line = __LINE__, Throwable next = null) {
        super(msg, file, line, next);
    }
    @nogc @safe pure nothrow this(string msg, Throwable next, string file = __FILE__, size_t line = __LINE__) {
        super(msg, file, line, next);
    }
}

/// ASSIMPエラーチェック
T enforceAsset(T)(
        T value,
        lazy const(char)[] msg = null,
        string file = __FILE__,
        size_t line = __LINE__)
        if (is(typeof((){if(!value){}}))) {
    if(!value) {
        auto errorMessage = format("%s : %s", fromStringz(aiGetErrorString()), msg);
        throw new AssetException(errorMessage, file, line);
    }
    return value;
}

/// シーンのアセット
class SceneAsset {

    /// 指定パスのシーンファイルを開く
    this(string path) {
        scene_ = enforceAsset(aiImportFile(
                    toStringz(path),
                    aiProcess_CalcTangentSpace
                    | aiProcess_Triangulate
                    | aiProcess_JoinIdenticalVertices
                    | aiProcess_SortByPType));
    }

    /// シーンの破棄
    ~this() nothrow {
        release();
    }

    /// シーンを生成する
    Scene createScene() const
    in {
        assert(scene_ !is null);
    } body {
        if(scene_.mRootNode is null) {
            return new Scene(null);
        }

        // マテリアル情報
        auto materials
            = scene_.mMaterials[0 .. scene_.mNumMaterials]
            .map!(m => createMaterial(m))
            .array;

        // メッシュ配列
        auto meshes
            = scene_.mMeshes[0 .. scene_.mNumMeshes]
            .map!(m => createMesh(m, materials))
            .array;

        // ルートノード
        auto root = createNode(scene_.mRootNode, meshes);

        return new Scene(root);
    }

    /// シーンの解放
    void release() nothrow {
        aiReleaseImport(scene_);
        scene_ = null;
    }

private:

    /// 文字列変換
    static string fromAiString(const(aiString) s) @safe pure {
        return s.data[0 .. s.length].idup;
    }

    /// ノードの生成
    Node createNode(const(aiNode)* node, const(Mesh)[] meshes) const {
        // ノード名
        auto name = fromAiString(node.mName);

        // 子ノード配列
        auto children
                = node.mChildren[0 .. node.mNumChildren]
                    .map!(c => createNode(c, meshes))
                    .array;

        // 変換行列
        auto a = node.mTransformation;
        auto trans = mat4(
                a.a1, a.a2, a.a3, a.a4,
                a.b1, a.b2, a.b3, a.b4,
                a.c1, a.c2, a.c3, a.c4,
                a.d1, a.d2, a.d3, a.d4);

        return new Node(name, meshes, children, trans);
    }

    /// マテリアルの生成
    Material createMaterial(const(aiMaterial)* material) const {
        // マテリアル名
        aiString aiName;
        aiGetMaterialString(material, AI_MATKEY_NAME, 0, 0, &aiName);
        auto name = fromAiString(aiName);

        aiColor4D color;

        // 表面色
        aiGetMaterialColor(material, AI_MATKEY_COLOR_DIFFUSE, 0, 0, &color);
        auto diffuse = fromAiColor(color);

        aiGetMaterialColor(material, AI_MATKEY_COLOR_SPECULAR, 0, 0, &color);

        // ハイライト色
        auto speculer = fromAiColor(color);

        aiGetMaterialColor(material, AI_MATKEY_COLOR_AMBIENT, 0, 0, &color);

        // 環境色
        auto ambient = fromAiColor(color);

        return new Material(name, diffuse, speculer, ambient);
    }

    /// 色情報の変換
    static Material.Color fromAiColor(ref const(aiColor4D) c) @safe nothrow pure @nogc {
        return Material.Color(c.r, c.g, c.b, c.a);
    }

    /// メッシュの生成
    Mesh createMesh(const(aiMesh)* mesh, const(Material)[] materials) const {
        // メッシュ名
        auto name = fromAiString(mesh.mName);

        // 頂点配列
        auto vertices
            = mesh.mVertices[0 .. mesh.mNumVertices]
                .map!(v => vec3(v.x, v.y, v.z))
                .array;

        // 法線配列
        const(vec3)[] normals;
        if(mesh.mNormals !is null) {
            normals = mesh.mNormals[0 .. mesh.mNumVertices]
                .map!(n => vec3(n.x, n.y, n.z))
                .array;
        }

        // 面配列。頂点数別にまとめる
        Appender!(uint[])[uint] faces;
        foreach(f; mesh.mFaces[0 .. mesh.mNumFaces]) {
            immutable n = f.mNumIndices;
            auto app = n in faces;
            if(app is null) {
                app = &(faces[n] = Appender!(uint[])());
            }
            app.put(f.mIndices[0 .. n]);
        }

        uint[][uint] facesArray;
        foreach(e; faces.byKeyValue) {
            facesArray[e.key] = e.value.data;
        }
        facesArray.rehash;

        // マテリアルの取得
        immutable mi = mesh.mMaterialIndex;
        auto material = (mi < materials.length) ? materials[mi] : null;
        return new Mesh(name, vertices, normals, facesArray, material);
    }

    /// シーンへのポインタ
    const(aiScene)* scene_;
}

