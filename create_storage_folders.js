const { initializeApp } = require('firebase/app');
const { getStorage, ref, uploadBytes, getDownloadURL } = require('firebase/storage');

// Firebase設定（実際のプロジェクトの設定に合わせてください）
const firebaseConfig = {
  apiKey: "AIzaSyBXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX",
  authDomain: "dating-food-app-82e38.firebaseapp.com",
  projectId: "dating-food-app-82e38",
  storageBucket: "dating-food-app-82e38.appspot.com",
  messagingSenderId: "123456789012",
  appId: "1:123456789012:web:abcdefghijklmnop"
};

// Firebase初期化
const app = initializeApp(firebaseConfig);
const storage = getStorage(app);

// 作成するフォルダ構造
const folders = [
  'profile-images',
  'user-images', 
  'user_images',
  'matches-images',
  'group-message-images',
  'group-images',
  'identity-documents',
  'images',
  'badge_photos'
];

async function createStorageFolders() {
  console.log('🔄 Firebase Storageフォルダ作成開始...');
  
  try {
    for (const folder of folders) {
      console.log(`📁 フォルダ作成中: ${folder}`);
      
      // 空のファイルをアップロードしてフォルダを作成
      const folderRef = ref(storage, `${folder}/.keep`);
      const emptyFile = new Uint8Array(0);
      
      await uploadBytes(folderRef, emptyFile, {
        contentType: 'application/octet-stream',
        customMetadata: {
          'createdAt': new Date().toISOString(),
          'purpose': 'folder_placeholder'
        }
      });
      
      console.log(`✅ フォルダ作成完了: ${folder}`);
    }
    
    console.log('🎉 すべてのフォルダ作成が完了しました！');
    
  } catch (error) {
    console.error('❌ フォルダ作成エラー:', error);
  }
}

// スクリプト実行
createStorageFolders(); 