function addDream() {
    const name = document.getElementById('userName').value;
    const dream = document.getElementById('userDream').value;
    const grid = document.getElementById('wallGrid');

    if (name && dream) {
        const card = document.createElement('div');
        card.className = 'dream-dream-card';
        card.innerHTML = `
            <div class="dream-card">
                <span class="card-number">#DREAMER</span>
                <h3>${name}</h3>
                <p>"${dream}"</p>
                <span class="tagline">Future JozEV Rider</span>
            </div>
        `;
        
        // Add to the top of the grid
        grid.prepend(card);

        // Clear inputs
        document.getElementById('userName').value = '';
        document.getElementById('userDream').value = '';
    } else {
        alert("Please share your name and your dream.");
    }
}
