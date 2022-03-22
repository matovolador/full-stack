<script>
import axios from "axios";

export default {
  data() {
    return {
      status: "pending...",
      message: "?",
    };
  },
  mounted() {
    axios.get("http://127.0.0.1:5050/api/health").then((response) => {
      this.status = response.status;
      console.log(response);
      console.log(this.status);
      if (this.status === 200) this.message = response.data.message;
    });
  },
};
</script>
<template>
  <div>
    <div>/health is: {{ status }}</div>
    <div>{{ message }}</div>
  </div>
</template>