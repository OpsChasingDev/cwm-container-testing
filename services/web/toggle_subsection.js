// Get all H4 elements with class 'subsection-toggle'
const toggles = document.querySelectorAll('.subsection-toggle');

// Loop through each H4 element
toggles.forEach(toggle => {
    // Add click event listener
    toggle.addEventListener('click', () => {
        // Toggle the visibility of report-links when H4 is clicked
        const reportLinks = toggle.nextElementSibling;
        if (reportLinks.style.display === 'none') {
            reportLinks.style.display = 'block';
        } else {
            reportLinks.style.display = 'none';
        }
    });
});