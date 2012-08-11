package dc

import "testing"

func Test_KeysGenerated(t *testing.T) {
  bytes := GenerateKey([]byte("FOO"))
  if string(bytes) != "4\220/%DCN000%/" {
    t.Errorf("generated wrong key: %s", string(bytes))
  }
}
