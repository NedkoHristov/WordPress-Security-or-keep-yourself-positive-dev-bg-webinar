<!DOCTYPE html>
<html <?php language_attributes(); ?>>
<head>
    <meta charset="<?php bloginfo( 'charset' ); ?>">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <?php wp_head(); ?>
</head>
<body <?php body_class(); ?>>
    <div class="backdoor-warning">
        ⚠️ THIS IS A NULLED THEME DEMO — Contains simulated backdoors for educational purposes
    </div>
    <header>
        <h1><?php bloginfo( 'name' ); ?></h1>
        <p><?php bloginfo( 'description' ); ?></p>
    </header>
    <main>
        <?php
        if ( have_posts() ) {
            while ( have_posts() ) {
                the_post();
                echo '<article>';
                echo '<h2>' . get_the_title() . '</h2>';
                the_content();
                echo '</article>';
            }
        }
        ?>
    </main>
    <?php wp_footer(); ?>
</body>
</html>
