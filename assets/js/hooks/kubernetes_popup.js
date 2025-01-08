const KubernetesPopup = {
  mounted() {
    const popup = this.el.querySelector('div')
    
    this.el.addEventListener('mousemove', (e) => {
      const rect = this.el.getBoundingClientRect()
      popup.style.position = 'fixed'
      popup.style.left = `${e.clientX}px`
      popup.style.top = `${e.clientY + 20}px` // 20px offset below cursor
    })
  }
}

export default KubernetesPopup 