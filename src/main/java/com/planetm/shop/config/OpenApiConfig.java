package com.planetm.shop.config;

import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.oas.models.info.Info;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class OpenApiConfig {
    @Bean
    OpenAPI planetMOpenApi() {
        return new OpenAPI().info(new Info().title("Planet-M Shop API").version("v1")
                .description("REST API for the Planet-M Shop furniture-linens store"));
    }
}
